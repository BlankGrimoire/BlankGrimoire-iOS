// SPDX-License-Identifier: MPL-2.0

import CoreFoundation
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

    /// Maximum accepted response body size in bytes.
    public let maxResponseBytes: Int

    /// Creates a per-site network policy.
    public init(
        baseURL: String,
        allowedHosts: [String] = [],
        maxRedirects: Int = 5,
        cookieHandling: CookieHandling = .automatic,
        timeout: TimeInterval = 30,
        defaultHeaders: [String: String] = [:],
        maxResponseBytes: Int = 10 * 1024 * 1024
    ) {
        self.baseURL = baseURL
        self.allowedHosts = allowedHosts
        self.maxRedirects = max(0, maxRedirects)
        self.cookieHandling = cookieHandling
        self.timeout = max(1, timeout)
        self.defaultHeaders = defaultHeaders
        self.maxResponseBytes = max(1, maxResponseBytes)
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
    case responseTooLarge(limit: Int)
    case unsupportedScheme(String)

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
        case .responseTooLarge(let limit):
            return "Response exceeds the \(limit)-byte limit"
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme)"
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
    private let session: URLSession
    private let logger: PluginLogger

    /// Per-handler cookie jar.
    ///
    /// `HTTPCookieStorage.shared` is process-wide and would leak cookies across
    /// sites. Each handler owns its own jar, keyed by `name|domain|path`.
    private var cookieJar: [String: HTTPCookie] = [:]

    /// Blocks automatic redirects so every hop passes through `validateHost`.
    private let redirectBlocker = RedirectBlocker()

    /// Creates a request handler for a specific site policy.
    public init(policy: SiteNetworkPolicy, logger: PluginLogger = ConsolePluginLogger()) {
        self.policy = policy
        self.logger = logger

        let config = URLSessionConfiguration.ephemeral
        // Cookie handling is manual and per-handler; URLSession must not read
        // or write the shared cookie storage behind our back.
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = policy.timeout
        config.timeoutIntervalForResource = policy.timeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: config)
    }

    /// Performs an HTTP request with policy enforcement.
    ///
    /// The request goes through:
    /// 1. URL/scheme validation
    /// 2. Host allowlist check (fail-closed)
    /// 3. Redirect handling (up to maxRedirects, method/body per status)
    /// 4. Per-site cookie injection/extraction (if enabled)
    /// 5. Response size limit
    public func perform(_ request: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: request.url) else {
            throw RequestHandlerError.invalidURL(request.url)
        }

        try validateScheme(url)
        try validateHost(url)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.uppercased()
        applyHeaders(request.headers, to: &urlRequest)

        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
        }

        applyCookies(for: url, to: &urlRequest)

        let (data, response) = try await performWithRedirectHandling(urlRequest, redirectCount: 0)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestHandlerError.invalidResponse
        }

        storeCookies(from: httpResponse)

        let headers = (httpResponse.allHeaderFields as? [String: String]) ?? [:]
        let body = decodedBody(data, response: httpResponse)

        logger.log(
            "HTTP \(request.method) \(Self.redactedURL(httpResponse.url ?? url)) -> \(httpResponse.statusCode)",
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

    /// Checks that the URL uses a supported, secure-for-production scheme.
    private func validateScheme(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased() else {
            throw RequestHandlerError.invalidURL(url.absoluteString)
        }
        guard scheme == "https" else {
            throw RequestHandlerError.unsupportedScheme(scheme)
        }
    }

    /// Checks if a host is allowed by the policy.
    ///
    /// An empty allowlist falls back to the host in `baseURL`. If neither is
    /// available the request is denied: an empty policy never means "allow all".
    private func validateHost(_ url: URL) throws {
        guard let host = url.host, !host.isEmpty else {
            throw RequestHandlerError.invalidURL(url.absoluteString)
        }

        let patterns = effectiveAllowedHosts()
        guard !patterns.isEmpty else {
            throw RequestHandlerError.hostNotAllowed(host)
        }

        guard patterns.contains(where: { HostMatcher.matches(pattern: $0, host: host) }) else {
            throw RequestHandlerError.hostNotAllowed(host)
        }
    }

    private func effectiveAllowedHosts() -> [String] {
        if !policy.allowedHosts.isEmpty {
            return policy.allowedHosts
        }
        guard let host = URL(string: policy.baseURL)?.host, !host.isEmpty else {
            return []
        }
        return [host]
    }

    private func applyHeaders(_ headers: [String: String]?, to request: inout URLRequest) {
        for (field, value) in policy.defaultHeaders where !Self.isReservedHeader(field) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        for (field, value) in headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    /// Apple does not guarantee reserved headers set through
    /// `httpAdditionalHeaders`; callers must provide them per request.
    private static func isReservedHeader(_ field: String) -> Bool {
        ["authorization", "cookie", "host"].contains(field.lowercased())
    }

    private func applyCookies(for url: URL, to request: inout URLRequest) {
        guard policy.cookieHandling == .automatic else { return }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return }

        var merged: [String: HTTPCookie] = [:]
        // Session cookies set by regular responses win over challenge cookies
        // for the same name/domain/path.
        for cookie in ChallengeCookieStore.shared.cookies(forHost: host)
        where Self.cookie(cookie, appliesTo: url) {
            merged[Self.cookieKey(cookie)] = cookie
        }
        for cookie in cookieJar.values where Self.cookie(cookie, appliesTo: url) {
            merged[Self.cookieKey(cookie)] = cookie
        }

        guard !merged.isEmpty else { return }
        for (field, value) in HTTPCookie.requestHeaderFields(with: Array(merged.values)) {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private func storeCookies(from response: HTTPURLResponse) {
        guard policy.cookieHandling == .automatic,
            let headerFields = response.allHeaderFields as? [String: String],
            let responseURL = response.url
        else {
            return
        }

        let now = Date()
        cookieJar = cookieJar.filter { _, cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires > now
        }

        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: responseURL) {
            cookieJar[Self.cookieKey(cookie)] = cookie
        }
    }

    private static func cookieKey(_ cookie: HTTPCookie) -> String {
        "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
    }

    private static func cookie(_ cookie: HTTPCookie, appliesTo url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if let expires = cookie.expiresDate, expires <= Date() {
            return false
        }
        if cookie.isSecure && url.scheme?.lowercased() != "https" {
            return false
        }

        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainMatches = host == domain || host.hasSuffix("." + domain)
        guard domainMatches else { return false }

        let path = cookie.path.isEmpty ? "/" : cookie.path
        return url.path.hasPrefix(path)
    }

    /// Decodes the body using the declared charset, falling back to UTF-8.
    private func decodedBody(_ data: Data, response: HTTPURLResponse) -> String {
        if let encodingName = response.textEncodingName,
            let encoding = String.Encoding(charSetName: encodingName),
            let body = String(data: data, encoding: encoding)
        {
            return body
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Hides query strings, which may contain tokens, from diagnostics.
    private static func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? "unknown"
        }
        if components.query != nil {
            components.query = "..."
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    /// Performs the request with manual redirect handling.
    ///
    /// `RedirectBlocker` prevents `URLSession` from following redirects, so
    /// this loop is the only place that can authorise a new host.
    private func performWithRedirectHandling(
        _ request: URLRequest,
        redirectCount: Int
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: redirectBlocker)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestHandlerError.invalidResponse
        }

        if let redirectURL = redirectTarget(for: httpResponse, relativeTo: request.url) {
            guard redirectCount < policy.maxRedirects else {
                throw RequestHandlerError.maxRedirectsExceeded
            }

            try validateScheme(redirectURL)
            try validateHost(redirectURL)

            var newRequest = URLRequest(url: redirectURL)
            newRequest.httpMethod = request.httpMethod
            newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields

            // 301/302/303 turn a non-GET request into GET, matching browsers
            // and `NativeBridgeImpl`. 307/308 preserve method and body.
            let status = httpResponse.statusCode
            let downgradesToGET = status == 301 || status == 302 || status == 303
            if downgradesToGET, request.httpMethod != "GET", request.httpMethod != "HEAD" {
                newRequest.httpMethod = "GET"
                newRequest.httpBody = nil
                newRequest.setValue(nil, forHTTPHeaderField: "Content-Type")
                newRequest.setValue(nil, forHTTPHeaderField: "Content-Length")
            } else {
                newRequest.httpBody = request.httpBody
            }

            // Never forward credentials across hosts.
            if redirectURL.host?.lowercased() != request.url?.host?.lowercased() {
                newRequest.setValue(nil, forHTTPHeaderField: "Authorization")
            }

            applyCookies(for: redirectURL, to: &newRequest)

            return try await performWithRedirectHandling(newRequest, redirectCount: redirectCount + 1)
        }

        let data = try await Self.collect(bytes, limit: policy.maxResponseBytes)
        return (data, response)
    }

    private func redirectTarget(for response: HTTPURLResponse, relativeTo base: URL?) -> URL? {
        guard (300...399).contains(response.statusCode) else {
            return nil
        }
        guard
            let location = response.value(forHTTPHeaderField: "Location")
                ?? response.allHeaderFields["Location"] as? String
        else {
            return nil
        }
        return URL(string: location, relativeTo: base)
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))
        for try await byte in bytes {
            if data.count >= limit {
                throw RequestHandlerError.responseTooLarge(limit: limit)
            }
            data.append(byte)
        }
        return data
    }
}

/// Rejects every HTTP redirect so `PluginRequestHandler` can validate each hop.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Host matching shared by the request handler and the JS bridge.
enum HostMatcher {
    /// Matches a host against a pattern (case-insensitive, subdomain-aware).
    static func matches(pattern: String, host: String) -> Bool {
        let pattern = pattern.lowercased()
        let host = host.lowercased()
        guard !pattern.isEmpty else { return false }

        if pattern == host {
            return true
        }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host.hasSuffix("." + suffix) || host == suffix
        }
        return host.hasSuffix("." + pattern)
    }

    static func isAllowed(host: String, patterns: [String], baseURL: String) -> Bool {
        let effective: [String]
        if patterns.isEmpty {
            guard let baseHost = URL(string: baseURL)?.host, !baseHost.isEmpty else {
                return false
            }
            effective = [baseHost]
        } else {
            effective = patterns
        }
        return effective.contains { matches(pattern: $0, host: host) }
    }
}

extension String.Encoding {
    fileprivate init?(charSetName: String) {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charSetName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }
        self = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
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
        self.requestHandler = PluginRequestHandler(policy: policy, logger: logger)
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
    ///
    /// Mirrors `PluginRequestHandler`: an empty allowlist falls back to the
    /// policy's base host and never allows every host.
    public nonisolated func isAllowed(_ url: String) -> Bool {
        guard let url = URL(string: url), let host = url.host else { return false }
        return HostMatcher.isAllowed(
            host: host,
            patterns: policy.allowedHosts,
            baseURL: policy.baseURL
        )
    }

    /// Disposes all resources (timers, etc.).
    public func dispose() {
        timerManager.dispose()
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
