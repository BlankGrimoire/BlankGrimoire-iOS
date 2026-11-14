// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Abstraction used by the UI to detect the theme of a user-entered site.
public protocol SiteThemeDetecting: Sendable {
    func detectTheme(for url: String) async throws -> ThemeDetectionResult
}

/// Default detector that builds a per-site network policy and runs `ThemeDetector`.
///
/// A dedicated `PluginRequestHandler` is created for every site so the
/// allowlist only contains the host the user explicitly entered (plus its
/// subdomains, handled by the request handler).
public final class DefaultSiteThemeDetector: SiteThemeDetecting {
    private let adapterStore: any AdapterStore
    private let logger: any PluginLogger

    public init(
        adapterStore: any AdapterStore,
        logger: any PluginLogger = ConsolePluginLogger()
    ) {
        self.adapterStore = adapterStore
        self.logger = logger
    }

    public func detectTheme(for url: String) async throws -> ThemeDetectionResult {
        guard
            let baseURL = SiteURL.baseURLString(from: url),
            let host = SiteURL.host(from: url)
        else {
            throw ThemeDetectorError.invalidURL(url)
        }

        let policy = SiteNetworkPolicy(
            baseURL: baseURL,
            allowedHosts: [host]
        )
        let requestHandler = PluginRequestHandler(policy: policy, logger: logger)
        let bridge = PluginBridge(policy: policy, logger: logger)
        let detector = ThemeDetector(
            adapterStore: adapterStore,
            requestHandler: requestHandler,
            bridge: bridge,
            logger: logger
        )
        defer { bridge.dispose() }
        return try await detector.detectTheme(for: baseURL)
    }
}
