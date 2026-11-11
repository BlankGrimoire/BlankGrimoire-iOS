// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

/// SwiftData representation of a user-configured site profile.
///
/// The domain value type is `SiteProfile`; this entity only exists so the
/// profile can be stored locally without leaking SwiftData into the UI layer.
@Model
public final class SiteProfileEntity {
    @Attribute(.unique) public var id: String
    public var name: String
    public var baseURL: String
    public var themeID: String
    public var themeVersion: String?
    public var selectorOverridesData: Data?
    public var isEnabled: Bool
    public var lastAccessedAt: Date?
    public var customHeadersData: Data?
    public var cookieHandlingRaw: String
    public var maxRedirects: Int
    public var timeout: TimeInterval

    /// Set when the stored payload cannot be decoded. The raw bytes are kept
    /// so a later save does not silently replace the user's data with defaults.
    @Transient private var selectorOverridesDecodeFailed = false
    @Transient private var customHeadersDecodeFailed = false

    public init(profile: SiteProfile) {
        self.id = profile.id
        self.name = profile.name
        self.baseURL = profile.baseURL
        self.themeID = profile.themeID
        self.themeVersion = profile.themeVersion
        self.selectorOverridesData = Self.encode(profile.selectorOverrides)
        self.isEnabled = profile.isEnabled
        self.lastAccessedAt = profile.lastAccessedAt
        self.customHeadersData = Self.encode(profile.customHeaders)
        self.cookieHandlingRaw = profile.cookieHandling.rawValue
        self.maxRedirects = profile.maxRedirects
        self.timeout = profile.timeout
    }

    /// Converts the stored entity back into the immutable domain value.
    public var profile: SiteProfile {
        let overrides: ThemeSelectorsOverrides
        if let decoded = Self.decode(ThemeSelectorsOverrides.self, from: selectorOverridesData) {
            overrides = decoded
        } else {
            selectorOverridesDecodeFailed = true
            overrides = ThemeSelectorsOverrides()
        }

        let headers: [String: String]
        if let decoded = Self.decode([String: String].self, from: customHeadersData) {
            headers = decoded
        } else {
            customHeadersDecodeFailed = true
            headers = [:]
        }

        return SiteProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            themeID: themeID,
            themeVersion: themeVersion,
            selectorOverrides: overrides,
            isEnabled: isEnabled,
            lastAccessedAt: lastAccessedAt,
            customHeaders: headers,
            cookieHandling: CookieHandling(rawValue: cookieHandlingRaw) ?? .automatic,
            maxRedirects: maxRedirects,
            timeout: timeout
        )
    }

    /// Applies the mutable parts of a domain value to an existing entity.
    public func apply(_ profile: SiteProfile) {
        name = profile.name
        baseURL = profile.baseURL
        themeID = profile.themeID
        themeVersion = profile.themeVersion
        if !selectorOverridesDecodeFailed {
            selectorOverridesData = Self.encode(profile.selectorOverrides)
        }
        isEnabled = profile.isEnabled
        lastAccessedAt = profile.lastAccessedAt
        if !customHeadersDecodeFailed {
            customHeadersData = Self.encode(profile.customHeaders)
        }
        cookieHandlingRaw = profile.cookieHandling.rawValue
        maxRedirects = max(0, profile.maxRedirects)
        timeout = max(1, profile.timeout)
    }

    /// Versioned envelope so future format changes can be migrated explicitly.
    private struct Payload<Value: Codable>: Codable {
        let version: Int
        let value: Value
    }

    private static func encode<T: Codable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(Payload(version: 1, value: value))
    }

    private static func decode<T: Codable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }

        if let payload = try? JSONDecoder().decode(Payload<T>.self, from: data), payload.version == 1 {
            return payload.value
        }
        // Legacy rows stored the bare value without an envelope.
        return try? JSONDecoder().decode(type, from: data)
    }
}
