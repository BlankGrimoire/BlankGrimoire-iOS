// SPDX-License-Identifier: MPL-2.0

import Foundation
import WebKit

/// A WebView-based request handler that executes JavaScript to solve challenges.
///
/// This handler loads the page in a real WKWebView, waits for JavaScript
/// execution (including Cloudflare Turnstile, hCaptcha, etc.), then extracts
/// the final HTML. Cookies are synced to ChallengeCookieStore for reuse.
public actor WebViewRequestHandler {
    private let policy: SiteNetworkPolicy
    private let logger: PluginLogger

    public init(policy: SiteNetworkPolicy, logger: PluginLogger = ConsolePluginLogger()) {
        self.policy = policy
        self.logger = logger
    }

    /// Performs a request using WKWebView, waiting for JS challenges to resolve.
    ///
    /// - Parameters:
    ///   - request: The HTTP request to perform
    ///   - timeout: Maximum time to wait for page load and JS execution
    /// - Returns: The final HTML after JavaScript execution
    public func perform(_ request: HttpRequest, timeout: TimeInterval = 30) async throws -> HttpResponse {
        guard let url = URL(string: request.url) else {
            throw RequestHandlerError.invalidURL(request.url)
        }

        try validateScheme(url)
        try validateHost(url)

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let loader = WebViewPageLoader(
                    url: url,
                    request: request,
                    policy: self.policy,
                    timeout: timeout,
                    logger: self.logger
                ) { result in
                    continuation.resume(with: result)
                }
                loader.start()
            }
        }
    }

    private func validateScheme(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw RequestHandlerError.unsupportedScheme(url.scheme ?? "unknown")
        }
    }

    private func validateHost(_ url: URL) throws {
        guard let host = url.host, !host.isEmpty else {
            throw RequestHandlerError.invalidURL(url.absoluteString)
        }
        let patterns = effectiveAllowedHosts()
        guard patterns.contains(where: { HostMatcher.matches(pattern: $0, host: host) }) else {
            throw RequestHandlerError.hostNotAllowed(host)
        }
    }

    private func effectiveAllowedHosts() -> [String] {
        if !policy.allowedHosts.isEmpty { return policy.allowedHosts }
        guard let host = URL(string: policy.baseURL)?.host, !host.isEmpty else { return [] }
        return [host]
    }
}

/// Internal WKWebView controller for loading pages and extracting HTML.
@MainActor
private final class WebViewPageLoader: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private let url: URL
    private let request: HttpRequest
    private let policy: SiteNetworkPolicy
    private let timeout: TimeInterval
    private let logger: PluginLogger
    private let completion: (Result<HttpResponse, Error>) -> Void

    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var hasCompleted = false

    init(
        url: URL,
        request: HttpRequest,
        policy: SiteNetworkPolicy,
        timeout: TimeInterval,
        logger: PluginLogger,
        completion: @escaping (Result<HttpResponse, Error>) -> Void
    ) {
        self.url = url
        self.request = request
        self.policy = policy
        self.timeout = timeout
        self.logger = logger
        self.completion = completion
        super.init()
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // Isolated per request

        // Apply cookies from ChallengeCookieStore
        let cookieStore = config.websiteDataStore.httpCookieStore
        for cookie in ChallengeCookieStore.shared.cookies(forHost: url.host ?? "") {
            cookieStore.setCookie(cookie)
        }

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        cookieStore.add(self)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.uppercased()
        urlRequest.timeoutInterval = timeout

        // Apply request body if present
        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
        }

        // Apply default headers from policy
        for (field, value) in policy.defaultHeaders where !Self.isReservedHeader(field) {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        // Apply per-request headers
        for (field, value) in request.headers ?? [:] where !Self.isReservedHeader(field) {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        webView?.load(urlRequest)

        // Start timeout
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            if !hasCompleted {
                hasCompleted = true
                cleanup()
                completion(.failure(RequestHandlerError.requestTimeout))
            }
        }
    }

    // MARK: - WKNavigationDelegate

    @MainActor
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Allow sub-frames (challenge widgets)
        if navigationAction.targetFrame?.isMainFrame != true {
            decisionHandler(.allow)
            return
        }

        // Validate host for main frame navigations (redirects and link clicks)
        if url.scheme?.lowercased() == "https",
            let host = url.host,
            effectiveAllowedHosts().contains(where: { HostMatcher.matches(pattern: $0, host: host) })
        {
            decisionHandler(.allow)
        } else if url.scheme == "about" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait a bit for JS to execute (Turnstile, etc.)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            await extractHTML()
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleError(error)
    }

    @MainActor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleError(error)
    }

    @MainActor
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleError(
            NSError(
                domain: "WebKitErrorDomain", code: 102,
                userInfo: [NSLocalizedDescriptionKey: "Web content process terminated"]))
    }

    // MARK: - WKHTTPCookieStoreObserver

    @MainActor
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let allowed = cookies.filter { self.isAllowedHost($0.domain) }
            for cookie in allowed {
                ChallengeCookieStore.shared.store([cookie], forHost: cookie.domain)
            }
        }
    }

    // MARK: - Private

    private func extractHTML() async {
        guard let webView, !hasCompleted else { return }

        do {
            let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
            let currentURL = webView.url?.absoluteString ?? url.absoluteString

            // Check if we still have a challenge
            if SiteChallengeDetector.isChallenge(status: 200, body: html) {
                logger.warn(
                    "WebView mode: challenge still present after JS execution", level: 1, context: ["url": currentURL])
                // Don't complete - let the manual ChallengeView handle it
                hasCompleted = true
                cleanup()
                completion(.failure(RequestHandlerError.networkError("Challenge not resolved by WebView")))
                return
            }

            hasCompleted = true
            cleanup()

            let response = HttpResponse(
                status: 200,
                url: currentURL,
                headers: [:],
                body: html
            )
            completion(.success(response))

        } catch {
            handleError(error)
        }
    }

    private func handleError(_ error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(.failure(RequestHandlerError.networkError(error.localizedDescription)))
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil

        if let webView {
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
            webView.navigationDelegate = nil
            self.webView = nil
        }
    }

    private func isAllowedHost(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return effectiveAllowedHosts().contains { pattern in
            let p = pattern.lowercased()
            return normalized == p || normalized.hasSuffix("." + p)
        }
    }

    private func effectiveAllowedHosts() -> [String] {
        if !policy.allowedHosts.isEmpty { return policy.allowedHosts }
        guard let host = URL(string: policy.baseURL)?.host, !host.isEmpty else { return [] }
        return [host]
    }

    private static func isReservedHeader(_ field: String) -> Bool {
        ["authorization", "cookie", "host"].contains(field.lowercased())
    }
}
