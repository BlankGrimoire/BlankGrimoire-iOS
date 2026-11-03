// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Represents a user-configured site with its associated theme and custom overrides.
public struct SiteProfile: Codable, Sendable, Equatable, Identifiable {
    /// Unique identifier for this site profile.
    public let id: String

    /// User-visible name for the site.
    public let name: String

    /// Base URL of the site (e.g., "https://example.org").
    public let baseURL: String

    /// ID of the theme adapter to use for this site.
    public let themeID: String

    /// Version of the theme adapter (optional; if nil, uses latest installed).
    public let themeVersion: String?

    /// Custom selector overrides for this specific site.
    public let selectorOverrides: ThemeSelectorsOverrides

    /// Whether this site is enabled for browsing.
    public let isEnabled: Bool

    /// Last time this site was accessed.
    public let lastAccessedAt: Date?

    /// Custom HTTP headers to send with requests to this site.
    public let customHeaders: [String: String]

    /// Cookie handling policy for this site.
    public let cookieHandling: CookieHandling

    /// Maximum redirects to follow for this site.
    public let maxRedirects: Int

    /// Request timeout for this site.
    public let timeout: TimeInterval

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
        timeout: TimeInterval = 30
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
        self.maxRedirects = maxRedirects
        self.timeout = timeout
    }

    /// Creates a SiteContext for use with the plugin engine.
    public func makeSiteContext() -> SiteContext {
        SiteContext(
            baseURL: baseURL,
            siteName: name,
            overrides: selectorOverrides
        )
    }

    /// Creates a network policy for this site.
    public func makeNetworkPolicy() -> SiteNetworkPolicy {
        SiteNetworkPolicy(
            baseURL: baseURL,
            allowedHosts: [URL(string: baseURL)?.host ?? ""],
            maxRedirects: maxRedirects,
            cookieHandling: cookieHandling,
            timeout: timeout,
            defaultHeaders: customHeaders
        )
    }

    /// Returns a copy with updated last accessed time.
    public func touched() -> SiteProfile {
        SiteProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            themeID: themeID,
            themeVersion: themeVersion,
            selectorOverrides: selectorOverrides,
            isEnabled: isEnabled,
            lastAccessedAt: Date(),
            customHeaders: customHeaders,
            cookieHandling: cookieHandling,
            maxRedirects: maxRedirects,
            timeout: timeout
        )
    }
}

/// Protocol for managing site profiles.
@MainActor
public protocol SiteProfileStore {
    /// Saves a site profile.
    func save(_ profile: SiteProfile) async throws

    /// Fetches a site profile by ID.
    func fetch(id: String) async throws -> SiteProfile?

    /// Fetches a site profile by base URL.
    func fetchByBaseURL(_ baseURL: String) async throws -> SiteProfile?

    /// Lists all site profiles.
    func listAll() async throws -> [SiteProfile]

    /// Lists enabled site profiles.
    func listEnabled() async throws -> [SiteProfile]

    /// Deletes a site profile.
    func delete(id: String) async throws

    /// Updates the last accessed time for a site.
    func touch(id: String) async throws
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
