// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Represents a user-configured site with its associated theme and custom overrides.
public struct SiteProfile: Codable, Sendable, Equatable, Identifiable {
    /// Unique identifier for this site profile.
    public var id: String

    /// User-visible name for the site.
    public var name: String

    /// Base URL of the site (e.g., "https://example.org").
    public var baseURL: String

    /// ID of the theme adapter to use for this site.
    public var themeID: String

    /// Version of the theme adapter (optional; if nil, uses latest installed).
    public var themeVersion: String?

    /// Custom selector overrides for this specific site.
    public var selectorOverrides: ThemeSelectorsOverrides

    /// Whether this site is enabled for browsing.
    public var isEnabled: Bool

    /// Last time this site was accessed.
    public var lastAccessedAt: Date?

    /// Custom HTTP headers to send with requests to this site.
    public var customHeaders: [String: String]

    /// Cookie handling policy for this site.
    public var cookieHandling: CookieHandling

    /// Maximum redirects to follow for this site.
    public var maxRedirects: Int

    /// Request timeout for this site.
    public var timeout: TimeInterval

    /// Whether this site should use WebView mode for requests that hit challenges.
    /// When enabled, the app will automatically try to solve JavaScript challenges
    /// (Cloudflare Turnstile, etc.) in a background WebView before falling back
    /// to the manual ChallengeView.
    public var usesWebViewMode: Bool

    /// Host templates declared by the active adapter, relative to this site's
    /// host (for example `api.{host}`). The session fills them from the adapter
    /// manifest; they are not user input. Optional so existing stored profiles
    /// decode without migration.
    public var networkHosts: [String]?

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        themeID: String,
        themeVersion: String? = nil,
        selectorOverrides: ThemeSelectorsOverrides = ThemeSelectorsOverrides(),
        isEnabled: Bool = true,
        lastAccessedAt: Date? = nil,
        customHeaders: [String: String] = [:],
        cookieHandling: CookieHandling = .automatic,
        maxRedirects: Int = 5,
        timeout: TimeInterval = 30,
        usesWebViewMode: Bool = false,
        networkHosts: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.themeID = themeID
        self.themeVersion = themeVersion
        self.selectorOverrides = selectorOverrides
        self.isEnabled = isEnabled
        self.lastAccessedAt = lastAccessedAt
        self.customHeaders = customHeaders
        self.cookieHandling = cookieHandling
        self.maxRedirects = max(0, maxRedirects)
        self.timeout = max(1, timeout)
        self.usesWebViewMode = usesWebViewMode
        self.networkHosts = networkHosts
    }

    /// Creates a SiteContext for use with the plugin engine.
    public func makeSiteContext() -> SiteContext {
        SiteContext(
            baseURL: baseURL,
            siteName: name,
            overrides: selectorOverrides
        )
    }

    /// Whether `baseURL` parses as an absolute URL with a host.
    public var hasValidBaseURL: Bool {
        guard let url = URL(string: baseURL), let host = url.host, !host.isEmpty else {
            return false
        }
        return url.scheme?.lowercased() == "https"
    }

    /// Creates a network policy for this site.
    ///
    /// `allowedHosts` always contains the site host. Adapter-declared
    /// `networkHosts` templates are expanded against that host and accepted
    /// only when they stay on the site's domain, so an adapter can reach its
    /// own API but never widen the allowlist elsewhere.
    public func makeNetworkPolicy() -> SiteNetworkPolicy {
        SiteNetworkPolicy(
            baseURL: baseURL,
            allowedHosts: Self.allowedHosts(baseURL: baseURL, networkHosts: networkHosts ?? []),
            maxRedirects: maxRedirects,
            cookieHandling: cookieHandling,
            timeout: timeout,
            defaultHeaders: customHeaders
        )
    }

    /// Returns a copy carrying the host templates declared by `adapterHosts`.
    public func withAdapterNetworkHosts(_ adapterHosts: [String]) -> SiteProfile {
        var copy = self
        copy.networkHosts = adapterHosts.isEmpty ? nil : adapterHosts
        return copy
    }

    /// Returns a copy that honours an adapter-declared WebView mode.
    ///
    /// The flag lives in the adapter manifest, not in the stored profile: a
    /// profile saved before the adapter declared it (or restored from storage
    /// that does not persist the field) would otherwise skip the hidden
    /// verification pass and surface a challenge error to the user. The
    /// manifest is authoritative in both directions, so switching to an
    /// adapter that does not need the hidden pass clears a stale value.
    public func withAdapterWebViewMode(_ enabled: Bool) -> SiteProfile {
        guard usesWebViewMode != enabled else { return self }
        var copy = self
        copy.usesWebViewMode = enabled
        return copy
    }

    /// Expands adapter host templates for `baseURL`.
    ///
    /// A template contains exactly one `{host}` placeholder and no scheme,
    /// port or path. The placeholder is replaced with the site host without a
    /// leading `www.`, and the result is kept only when it equals that host or
    /// is a subdomain of it.
    static func allowedHosts(baseURL: String, networkHosts: [String]) -> [String] {
        guard let rawHost = URL(string: baseURL)?.host?.lowercased(), !rawHost.isEmpty else {
            return []
        }
        var hosts = [rawHost]
        let domain = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if domain != rawHost, !hosts.contains(domain) {
            hosts.append(domain)
        }
        for template in networkHosts {
            guard let expanded = expandHostTemplate(template, domain: domain),
                !hosts.contains(expanded)
            else {
                continue
            }
            hosts.append(expanded)
        }
        return hosts
    }

    static func expandHostTemplate(_ template: String, domain: String) -> String? {
        let parts = template.lowercased().components(separatedBy: "{host}")
        guard parts.count == 2 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        for part in parts {
            guard part.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        }
        let expanded = parts[0] + domain + parts[1]
        guard expanded == domain || expanded.hasSuffix(".\(domain)") else { return nil }
        return expanded
    }

    /// Returns a copy with updated last accessed time.
    public func touched() -> SiteProfile {
        // `var copy = self` keeps this in sync when a field is added; building
        // a new profile by hand silently dropped fields in the past.
        var copy = self
        copy.lastAccessedAt = Date()
        return copy
    }
}

/// Errors for site profile operations.
public enum SiteProfileError: Error, LocalizedError, Sendable, Equatable {
    case notFound(String)
    case alreadyExists(String)
    case invalidURL(String)
    case themeNotInstalled(String)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Site profile not found: \(id)"
        case .alreadyExists(let id):
            return "Site profile already exists: \(id)"
        case .invalidURL(let url):
            return "Invalid site URL: \(url)"
        case .themeNotInstalled(let id):
            return "Theme not installed: \(id)"
        case .storageError(let msg):
            return "Storage error: \(msg)"
        }
    }
}
