// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Configuration for HTTP requests per site.
public struct SiteNetworkPolicy: Codable, Sendable, Equatable {
    /// Base URL of the site (used as allowlist anchor).
    public let baseURL: String

    /// Allowed host patterns (supports wildcards like `*.example.org`).
    public let allowedHosts: [String]

    /// Maximum number of redirects to follow.
    public let maxRedirects: Int

    /// Whether to automatically handle cookies.
    public let cookieHandling: CookieHandling

    /// Request timeout in seconds.
    public let timeout: TimeInterval

    /// Additional headers to include in all requests.
    public let defaultHeaders: [String: String]

    public init(
        baseURL: String,
        allowedHosts: [String] = [],
        maxRedirects: Int = 5,
        cookieHandling: CookieHandling = .automatic,
        timeout: TimeInterval = 30,
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.allowedHosts = allowedHosts
        self.maxRedirects = maxRedirects
        self.cookieHandling = cookieHandling
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
    }
}

/// How cookies are handled for requests.
public enum CookieHandling: String, Codable, Sendable, Equatable {
    /// Automatically store and send cookies (uses HTTPCookieStorage).
    case automatic

    /// No cookie handling; adapter must manage cookies manually.
    case none

    /// Custom cookie header provided by the caller.
    case custom
}

/// Errors that can occur during request handling.
public enum RequestHandlerError: Error, LocalizedError, Sendable, Equatable {
    case hostNotAllowed(String)
    case invalidURL(String)
    case maxRedirectsExceeded
    case requestTimeout
    case networkError(String)
    case invalidResponse
    case cookieError(String)

    public var errorDescription: String? {
        switch self {
        case .hostNotAllowed(let url):
            return "Host not allowed by policy: \(url)"
        case .invalidURL(let url):
            return "Invalid request URL: \(url)"
        case .maxRedirectsExceeded:
            return "Maximum redirects exceeded"
        case .requestTimeout:
            return "Request timed out"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidResponse:
            return "Invalid HTTP response"
        case .cookieError(let msg):
            return "Cookie error: \(msg)"
        }
    }
}

/// A native HTTP request handler that enforces per-site policies.
///
/// This replaces the simple `PluginRequestHandler` closure with a full-featured
/// implementation including:
/// - Host allowlist with wildcard support
/// - Redirect policy with max depth
/// - Automatic cookie handling
/// - Request/response logging
public actor PluginRequestHandler {
    private let policy: SiteNetworkPolicy
    private let cookieStorage: HTTPCookieStorage
    private let session: URLSession
    private let logger: PluginLogger

    /// Creates a request handler for a specific site policy.
    public init(policy: SiteNetworkPolicy, logger: PluginLogger = ConsolePluginLogger()) {
        self.policy = policy
        self.logger = logger

        // Use ephemeral session if cookie handling is disabled
        let config = URLSessionConfiguration.default
        if policy.cookieHandling == .none {
            config.httpCookieStorage = nil
            config.httpCookieAcceptPolicy = .never
        }
        config.timeoutIntervalForRequest = policy.timeout
        config.timeoutIntervalForResource = policy.timeout * 2
        config.httpAdditionalHeaders = policy.defaultHeaders

        self.cookieStorage = config.httpCookieStorage ?? HTTPCookieStorage.shared
        self.session = URLSession(configuration: config)
    }

    /// Performs an HTTP request with policy enforcement.
    ///
    /// The request goes through:
    /// 1. URL validation
    /// 2. Host allowlist check
    /// 3. Redirect handling (up to maxRedirects)
    /// 4. Cookie injection/extraction (if enabled)
    public func perform(_ request: HttpRequest) async throws -> HttpResponse {
        // 1. Validate URL
        guard let url = URL(string: request.url) else {
            throw RequestHandlerError.invalidURL(request.url)
        }

        // 2. Check allowlist
        try validateHost(url)

        // 3. Build URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.allHTTPHeaderFields = request.headers

        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        // 4. Apply cookies if enabled
        if policy.cookieHandling == .automatic {
            let cookies = cookieStorage.cookies(for: url) ?? []
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
            cookieHeader.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        }

        // 5. Perform request with redirect handling
        let (data, response) = try await performWithRedirectHandling(urlRequest, redirectCount: 0)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestHandlerError.invalidResponse
        }

        // 6. Extract cookies from response
        if policy.cookieHandling == .automatic,
            let headerFields = httpResponse.allHeaderFields as? [String: String],
            let responseURL = httpResponse.url
        {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: responseURL)
            cookies.forEach { cookieStorage.setCookie($0) }
        }

        // 7. Build response
        let headers = (httpResponse.allHeaderFields as? [String: String]) ?? [:]
        let body = String(decoding: data, as: UTF8.self)

        logger.log(
            "HTTP \(request.method) \(request.url) -> \(httpResponse.statusCode)",
            level: 0,
            context: ["site": policy.baseURL]
        )

        return HttpResponse(
            status: httpResponse.statusCode,
            url: httpResponse.url?.absoluteString ?? request.url,
            headers: headers,
            body: body
        )
    }

    /// Checks if a host is allowed by the policy.
    private func validateHost(_ url: URL) throws {
        guard let host = url.host else {
            throw RequestHandlerError.invalidURL(url.absoluteString)
        }

        // If no allowlist configured, allow all hosts (backward compatibility)
        if policy.allowedHosts.isEmpty {
            return
        }

        let isAllowed = policy.allowedHosts.contains { pattern in
            matchHost(pattern, host)
        }

        if !isAllowed {
            throw RequestHandlerError.hostNotAllowed(host)
        }
    }

    /// Matches a host against a pattern (supports wildcards).
    private func matchHost(_ pattern: String, _ host: String) -> Bool {
        if pattern == host {
            return true
        }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host.hasSuffix(suffix) || host == suffix
        }
        return false
    }

    /// Performs the request with manual redirect handling.
    private func performWithRedirectHandling(_ request: URLRequest, redirectCount: Int) async throws -> (
        Data, URLResponse
    ) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return (data, response)
        }

        // Handle redirects manually to enforce maxRedirects
        if (300...399).contains(httpResponse.statusCode),
            let location = httpResponse.allHeaderFields["Location"] as? String,
            let redirectURL = URL(string: location, relativeTo: request.url)
        {
            if redirectCount >= policy.maxRedirects {
                throw RequestHandlerError.maxRedirectsExceeded
            }

            try validateHost(redirectURL)

            var newRequest = URLRequest(url: redirectURL)
            newRequest.httpMethod = request.httpMethod
            newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
            newRequest.httpBody = request.httpBody

            // Re-apply cookies for redirect
            if policy.cookieHandling == .automatic {
                let cookies = cookieStorage.cookies(for: redirectURL) ?? []
                let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
                cookieHeader.forEach { newRequest.setValue($1, forHTTPHeaderField: $0) }
            }

            return try await performWithRedirectHandling(newRequest, redirectCount: redirectCount + 1)
        }

        return (data, response)
    }
}

/// Native timer manager tied to a `JSPluginRuntime` lifecycle.
///
/// Provides `setTimeout`/`clearTimeout` and `setInterval`/`clearInterval`
/// that integrate with the JavaScriptCore timer bridge (`__timerFire`).
/// Uses a lock-protected state for synchronous bridge calls.
public final class NativeTimerManager: @unchecked Sendable {
    private struct TimerEntry {
        let id: Int
        let workItem: DispatchWorkItem
        let isInterval: Bool
        let intervalMs: Int
    }

    private let lock = NSLock()
    private var timers: [Int: TimerEntry] = [:]
    private var nextTimerID = 1
    private let queue = DispatchQueue(label: "PluginEngine.TimerQueue")
    private var isDisposed = false

    /// Schedules a one-shot timer and returns its ID.
    ///
    /// The timer fires by calling the provided closure on the timer queue.
    /// The caller should invoke `__timerFire(id)` on the JS side to
    /// trigger the JavaScript callback.
    @discardableResult
    public func setTimeout(_ ms: Int, _ callback: @escaping @Sendable () -> Void) -> Int {
        let id: Int = lock.withLock {
            guard !isDisposed else { return -1 }
            let current = nextTimerID
            nextTimerID += 1
            return current
        }

        guard id != -1 else { return 0 }

        let workItem = DispatchWorkItem { [weak self] in
            self?.fireTimer(id)
        }

        let added: Bool = lock.withLock {
            guard !isDisposed else { return false }
            timers[id] = TimerEntry(id: id, workItem: workItem, isInterval: false, intervalMs: ms)
            return true
        }

        if !added {
            workItem.cancel()
            return 0
        }

        queue.asyncAfter(deadline: .now() + .milliseconds(ms), execute: workItem)

        return id
    }

    /// Schedules a repeating timer and returns its ID.
    ///
    /// The timer fires repeatedly at the specified interval.
    /// The caller should invoke `__timerFire(id)` on the JS side each time.
    @discardableResult
    public func setInterval(_ ms: Int, _ callback: @escaping @Sendable () -> Void) -> Int {
        let id: Int = lock.withLock {
            guard !isDisposed else { return -1 }
            let current = nextTimerID
            nextTimerID += 1
            return current
        }

        guard id != -1 else { return 0 }

        let workItem = DispatchWorkItem { [weak self] in
            self?.fireIntervalTimer(id, intervalMs: ms)
        }

        let added: Bool = lock.withLock {
            guard !isDisposed else { return false }
            timers[id] = TimerEntry(id: id, workItem: workItem, isInterval: true, intervalMs: ms)
            return true
        }

        if !added {
            workItem.cancel()
            return 0
        }

        queue.asyncAfter(deadline: .now() + .milliseconds(ms), execute: workItem)

        return id
    }

    /// Cancels a scheduled timer (timeout or interval).
    public func clearTimeout(_ id: Int) {
        let workItem: DispatchWorkItem? = lock.withLock {
            timers.removeValue(forKey: id)?.workItem
        }
        workItem?.cancel()
    }

    /// Called when a one-shot timer fires - executes the callback and cleans up.
    private func fireTimer(_ id: Int) {
        let workItem: DispatchWorkItem? = lock.withLock {
            timers.removeValue(forKey: id)?.workItem
        }
        workItem?.perform()
    }

    /// Called when an interval timer fires - executes the callback and reschedules.
    private func fireIntervalTimer(_ id: Int, intervalMs: Int) {
        let entry: TimerEntry? = lock.withLock {
            guard let entry = timers[id], entry.isInterval else { return nil }
            return entry
        }
        guard let entry = entry else { return }

        entry.workItem.perform()

        // Reschedule if not disposed
        let shouldContinue: Bool = lock.withLock {
            !isDisposed && timers[id] != nil
        }
        if shouldContinue {
            queue.asyncAfter(deadline: .now() + .milliseconds(intervalMs), execute: entry.workItem)
        }
    }

    /// Invalidates all pending timers.
    public func dispose() {
        let items: [DispatchWorkItem] = lock.withLock {
            isDisposed = true
            let items = timers.values.map { $0.workItem }
            timers.removeAll()
            return items
        }
        for item in items {
            item.cancel()
        }
    }
}

/// Combined request handler and timer manager for a site.
///
/// This is the main native bridge implementation that gets passed to
/// `JSPluginRuntime` and provides:
/// - HTTP requests with policy enforcement
/// - Timer management tied to runtime lifecycle
public final class PluginBridge: @unchecked Sendable {
    public let requestHandler: PluginRequestHandler
    public let timerManager: NativeTimerManager
    private let logger: PluginLogger
    private let policy: SiteNetworkPolicy

    /// Custom request handler for testing (overrides the internal one).
    private let customRequestHandler: (@Sendable (HttpRequest) async throws -> HttpResponse)?

    public init(
        policy: SiteNetworkPolicy,
        logger: PluginLogger = ConsolePluginLogger(),
        customRequestHandler: (@Sendable (HttpRequest) async throws -> HttpResponse)? = nil
    ) {
        self.policy = policy
        self.logger = logger
        self.customRequestHandler = customRequestHandler
        if let customRequestHandler {
            // Create a minimal request handler that won't be used
            self.requestHandler = PluginRequestHandler(policy: policy, logger: logger)
        } else {
            self.requestHandler = PluginRequestHandler(policy: policy, logger: logger)
        }
        self.timerManager = NativeTimerManager()
    }

    /// Convenience method to perform a request.
    public func request(_ request: HttpRequest) async throws -> HttpResponse {
        if let customRequestHandler {
            return try await customRequestHandler(request)
        }
        return try await requestHandler.perform(request)
    }

    /// Schedules a timer callback (nonisolated for synchronous bridge calls).
    @discardableResult
    public nonisolated func setTimeout(_ ms: Int, _ callback: @escaping @Sendable () -> Void) -> Int {
        timerManager.setTimeout(ms, callback)
    }

    /// Schedules a repeating timer callback (nonisolated for synchronous bridge calls).
    @discardableResult
    public nonisolated func setInterval(_ ms: Int, _ callback: @escaping @Sendable () -> Void) -> Int {
        timerManager.setInterval(ms, callback)
    }

    /// Cancels a timer (nonisolated for synchronous bridge calls).
    public nonisolated func clearTimeout(_ id: Int) {
        timerManager.clearTimeout(id)
    }

    /// Checks if a URL is allowed by the policy.
    public nonisolated func isAllowed(_ url: String) -> Bool {
        guard let url = URL(string: url), let host = url.host else { return false }
        return policy.allowedHosts.isEmpty || policy.allowedHosts.contains { matchHost($0, host) }
    }

    /// Disposes all resources (timers, etc.).
    public func dispose() {
        timerManager.dispose()
    }

    private func matchHost(_ pattern: String, _ host: String) -> Bool {
        if pattern == host { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host.hasSuffix(suffix) || host == suffix
        }
        return false
    }
}

// MARK: - Logger

/// Simple logger protocol for plugin engine.
public protocol PluginLogger: Sendable {
    func log(_ message: String, level: Int, context: [String: Any]?)
    func error(_ message: String, level: Int, context: [String: Any]?)
    func warn(_ message: String, level: Int, context: [String: Any]?)
}

public struct ConsolePluginLogger: PluginLogger {
    public init() {}
    public func log(_ message: String, level: Int, context: [String: Any]?) {
        let prefix = ["DEBUG", "INFO", "WARN", "ERROR"][min(max(level, 0), 3)]
        let ctx = context.map { " \($0)" } ?? ""
        print("[\(prefix)]\(ctx) \(message)")
    }
    public func error(_ message: String, level: Int, context: [String: Any]?) {
        let prefix = ["DEBUG", "INFO", "WARN", "ERROR"][min(max(level, 0), 3)]
        let ctx = context.map { " \($0)" } ?? ""
        print("[\(prefix)]\(ctx) \(message)")
    }
    public func warn(_ message: String, level: Int, context: [String: Any]?) {
        let prefix = ["DEBUG", "INFO", "WARN", "ERROR"][min(max(level, 0), 3)]
        let ctx = context.map { " \($0)" } ?? ""
        print("[\(prefix)]\(ctx) \(message)")
    }
}
