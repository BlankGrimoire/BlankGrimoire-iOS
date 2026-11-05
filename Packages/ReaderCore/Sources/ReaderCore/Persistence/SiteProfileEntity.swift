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
        SiteProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            themeID: themeID,
            themeVersion: themeVersion,
            selectorOverrides: Self.decode(ThemeSelectorsOverrides.self, from: selectorOverridesData)
                ?? ThemeSelectorsOverrides(),
            isEnabled: isEnabled,
            lastAccessedAt: lastAccessedAt,
            customHeaders: Self.decode([String: String].self, from: customHeadersData) ?? [:],
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
        selectorOverridesData = Self.encode(profile.selectorOverrides)
        isEnabled = profile.isEnabled
        lastAccessedAt = profile.lastAccessedAt
        customHeadersData = Self.encode(profile.customHeaders)
        cookieHandlingRaw = profile.cookieHandling.rawValue
        maxRedirects = profile.maxRedirects
        timeout = profile.timeout
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
