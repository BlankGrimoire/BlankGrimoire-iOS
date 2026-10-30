// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

// MARK: - Contract Models (mirrors SDK @blankgrimoire/types)

/// ISO 8601 date-time string
public typealias ISODateString = String

/// Absolute URL, or URL relative to the site `baseURL`
public typealias URLString = String

/// Publication status
public enum MangaStatus: String, Codable, Sendable {
    case ongoing
    case completed
    case hiatus
    case cancelled
    case unknown
}

/// Content rating
public enum ContentRating: String, Codable, Sendable {
    case safe
    case suggestive
    case mature
    case unknown
}

/// Site attribution
public struct Attribution: Codable, Sendable {
    public let siteName: String
    public let siteURL: URLString
    public let logoURL: URLString?
    public let credits: String?

    public init(siteName: String, siteURL: URLString, logoURL: URLString? = nil, credits: String? = nil) {
        self.siteName = siteName
        self.siteURL = siteURL
        self.logoURL = logoURL
        self.credits = credits
    }
}

/// Manga summary (search result item)
public struct MangaSummary: Codable, Sendable, Identifiable {
    public let key: String
    public let title: String
    public let coverURL: URLString?

    public var id: String { key }

    public init(key: String, title: String, coverURL: URLString? = nil) {
        self.key = key
        self.title = title
        self.coverURL = coverURL
    }
}

/// Manga details (extends summary)
public struct MangaDetails: Codable, Sendable, Identifiable {
    public let key: String
    public let title: String
    public let coverURL: URLString?
    public let altTitles: [String]?
    public let authors: [String]?
    public let artists: [String]?
    public let synopsis: String?
    public let tags: [String]?
    public let status: MangaStatus
    public let contentRating: ContentRating
    public let attribution: Attribution?

    public var id: String { key }

    public init(
        key: String,
        title: String,
        coverURL: URLString? = nil,
        altTitles: [String]? = nil,
        authors: [String]? = nil,
        artists: [String]? = nil,
        synopsis: String? = nil,
        tags: [String]? = nil,
        status: MangaStatus,
        contentRating: ContentRating,
        attribution: Attribution? = nil
    ) {
        self.key = key
        self.title = title
        self.coverURL = coverURL
        self.altTitles = altTitles
        self.authors = authors
        self.artists = artists
        self.synopsis = synopsis
        self.tags = tags
        self.status = status
        self.contentRating = contentRating
        self.attribution = attribution
    }
}

/// Chapter
public struct Chapter: Codable, Sendable, Identifiable {
    public let key: String
    public let title: String?
    public let number: Double?
    public let volume: Double?
    public let language: String?
    public let publishedAt: ISODateString?
    public let group: String?

    public var id: String { key }

    public init(
        key: String,
        title: String? = nil,
        number: Double? = nil,
        volume: Double? = nil,
        language: String? = nil,
        publishedAt: ISODateString? = nil,
        group: String? = nil
    ) {
        self.key = key
        self.title = title
        self.number = number
        self.volume = volume
        self.language = language
        self.publishedAt = publishedAt
        self.group = group
    }
}

/// Page
public struct Page: Codable, Sendable, Identifiable {
    public let index: Int
    public let imageURL: URLString
    public let headers: [String: String]?

    public var id: String { "\(index)" }

    public init(index: Int, imageURL: URLString, headers: [String: String]? = nil) {
        self.index = index
        self.imageURL = imageURL
        self.headers = headers
    }
}

/// Paged result
public struct PagedResult<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let hasNextPage: Bool

    public init(items: [T], hasNextPage: Bool) {
        self.items = items
        self.hasNextPage = hasNextPage
    }
}

/// Search query
public struct SearchQuery: Codable, Sendable {
    public let text: String?
    public let page: Int
    public let filters: [String: String]?

    public init(text: String? = nil, page: Int = 1, filters: [String: String]? = nil) {
        self.text = text
        self.page = page
        self.filters = filters
    }
}

// MARK: - Theme Adapter Models

/// Theme detection signature
public struct ThemeSignature: Codable, Sendable, Equatable {
    public let metaGenerator: String?
    public let selectors: [String]?
    public let scriptSrc: [String]?
    public let probePaths: [String]?
    public let minScore: Int

    public init(
        metaGenerator: String? = nil,
        selectors: [String]? = nil,
        scriptSrc: [String]? = nil,
        probePaths: [String]? = nil,
        minScore: Int
    ) {
        self.metaGenerator = metaGenerator
        self.selectors = selectors
        self.scriptSrc = scriptSrc
        self.probePaths = probePaths
        self.minScore = minScore
    }
}

/// Theme selectors for declarative extraction
public struct ThemeSelectors: Codable, Sendable, Equatable {
    public struct SearchSelectors: Codable, Sendable, Equatable {
        public let path: String
        public let item: String
        public let title: String
        public let link: String
        public let cover: String?
        public let nextPage: String?

        public init(
            path: String, item: String, title: String, link: String, cover: String? = nil, nextPage: String? = nil
        ) {
            self.path = path
            self.item = item
            self.title = title
            self.link = link
            self.cover = cover
            self.nextPage = nextPage
        }
    }

    public struct DetailsSelectors: Codable, Sendable, Equatable {
        public let title: String
        public let cover: String?
        public let synopsis: String?
        public let authors: String?
        public let artists: String?
        public let altTitles: String?
        public let tags: String?
        public let status: String?
        public let contentRating: String?

        public init(
            title: String,
            cover: String? = nil,
            synopsis: String? = nil,
            authors: String? = nil,
            artists: String? = nil,
            altTitles: String? = nil,
            tags: String? = nil,
            status: String? = nil,
            contentRating: String? = nil
        ) {
            self.title = title
            self.cover = cover
            self.synopsis = synopsis
            self.authors = authors
            self.artists = artists
            self.altTitles = altTitles
            self.tags = tags
            self.status = status
            self.contentRating = contentRating
        }
    }

    public struct ChaptersSelectors: Codable, Sendable, Equatable {
        public let item: String
        public let link: String
        public let title: String?
        public let date: String?
        public let order: String  // "asc" | "desc"

        public init(item: String, link: String, title: String? = nil, date: String? = nil, order: String) {
            self.item = item
            self.link = link
            self.title = title
            self.date = date
            self.order = order
        }
    }

    public struct PagesConfig: Codable, Sendable, Equatable {
        public let strategies: [ExtractionStrategy]

        public init(strategies: [ExtractionStrategy]) {
            self.strategies = strategies
        }
    }

    public struct AttributionSelectors: Codable, Sendable, Equatable {
        public let logo: String?
        public let credits: String?

        public init(logo: String? = nil, credits: String? = nil) {
            self.logo = logo
            self.credits = credits
        }
    }

    public let search: SearchSelectors
    public let details: DetailsSelectors
    public let chapters: ChaptersSelectors
    public let pages: PagesConfig
    public let attribution: AttributionSelectors?

    public init(
        search: SearchSelectors,
        details: DetailsSelectors,
        chapters: ChaptersSelectors,
        pages: PagesConfig,
        attribution: AttributionSelectors? = nil
    ) {
        self.search = search
        self.details = details
        self.chapters = chapters
        self.pages = pages
        self.attribution = attribution
    }
}

/// Extraction strategies
public enum ExtractionStrategy: Codable, Sendable, Equatable {
    case css(CSSStrategy)
    case scriptJSON(ScriptJSONStrategy)
    case hydration(HydrationStrategy)
    case ajax(AjaxStrategy)

    enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)

        switch kind {
        case "css":
            let strategy = try CSSStrategy(from: decoder)
            self = .css(strategy)
        case "scriptJSON":
            let strategy = try ScriptJSONStrategy(from: decoder)
            self = .scriptJSON(strategy)
        case "hydration":
            let strategy = try HydrationStrategy(from: decoder)
            self = .hydration(strategy)
        case "ajax":
            let strategy = try AjaxStrategy(from: decoder)
            self = .ajax(strategy)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unknown strategy kind: \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .css(let strategy):
            try container.encode("css", forKey: .kind)
            try strategy.encode(to: encoder)
        case .scriptJSON(let strategy):
            try container.encode("scriptJSON", forKey: .kind)
            try strategy.encode(to: encoder)
        case .hydration(let strategy):
            try container.encode("hydration", forKey: .kind)
            try strategy.encode(to: encoder)
        case .ajax(let strategy):
            try container.encode("ajax", forKey: .kind)
            try strategy.encode(to: encoder)
        }
    }
}

public struct CSSStrategy: Codable, Sendable, Equatable {
    public let kind: String
    public let image: String
    public let srcAttributes: [String]
    public let headers: [String: String]?

    public init(image: String, srcAttributes: [String], headers: [String: String]? = nil) {
        self.kind = "css"
        self.image = image
        self.srcAttributes = srcAttributes
        self.headers = headers
    }

    private enum CodingKeys: String, CodingKey {
        case kind, image, srcAttributes, headers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        image = try container.decode(String.self, forKey: .image)
        srcAttributes = try container.decode([String].self, forKey: .srcAttributes)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
    }
}

public struct ScriptJSONStrategy: Codable, Sendable, Equatable {
    public let kind: String
    public let pattern: String
    public let path: String
    public let base64: Bool?

    public init(pattern: String, path: String, base64: Bool? = nil) {
        self.kind = "scriptJSON"
        self.pattern = pattern
        self.path = path
        self.base64 = base64
    }

    private enum CodingKeys: String, CodingKey {
        case kind, pattern, path, base64
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        pattern = try container.decode(String.self, forKey: .pattern)
        path = try container.decode(String.self, forKey: .path)
        base64 = try container.decodeIfPresent(Bool.self, forKey: .base64)
    }
}

public struct HydrationStrategy: Codable, Sendable, Equatable {
    public let kind: String
    public let framework: String  // "next" | "nuxt"
    public let path: String?

    public init(framework: String, path: String? = nil) {
        self.kind = "hydration"
        self.framework = framework
        self.path = path
    }

    private enum CodingKeys: String, CodingKey {
        case kind, framework, path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        framework = try container.decode(String.self, forKey: .framework)
        path = try container.decodeIfPresent(String.self, forKey: .path)
    }
}

public final class AjaxStrategy: Codable, Sendable, Equatable {
    public let kind: String
    public let method: String  // "GET" | "POST"
    public let path: String
    public let body: String?
    public let `then`: ExtractionStrategy

    public init(method: String, path: String, body: String? = nil, then: ExtractionStrategy) {
        self.kind = "ajax"
        self.method = method
        self.path = path
        self.body = body
        self.then = then
    }

    private enum CodingKeys: String, CodingKey {
        case kind, method, path, body, `then`
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        method = try container.decode(String.self, forKey: .method)
        path = try container.decode(String.self, forKey: .path)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        then = try container.decode(ExtractionStrategy.self, forKey: .then)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(method, forKey: .method)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(then, forKey: .then)
    }

    public static func == (lhs: AjaxStrategy, rhs: AjaxStrategy) -> Bool {
        return lhs.method == rhs.method && lhs.path == rhs.path && lhs.body == rhs.body && lhs.then == rhs.then
    }
}

/// Theme adapter
public struct ThemeAdapter: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let detectionSignature: ThemeSignature
    public let selectors: ThemeSelectors

    public init(
        id: String,
        name: String,
        version: String,
        detectionSignature: ThemeSignature,
        selectors: ThemeSelectors
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.detectionSignature = detectionSignature
        self.selectors = selectors
    }
}

/// Site context (user-selected site)
public struct SiteContext: Codable, Sendable, Equatable {
    public let baseURL: String
    public let siteName: String
    public let overrides: ThemeSelectorsOverrides

    public init(baseURL: String, siteName: String, overrides: ThemeSelectorsOverrides) {
        self.baseURL = baseURL
        self.siteName = siteName
        self.overrides = overrides
    }
}

/// User selector overrides (deep partial)
public struct ThemeSelectorsOverrides: Codable, Sendable, Equatable {
    public struct SearchOverrides: Codable, Sendable, Equatable {
        public let path: String?
        public let item: String?
        public let title: String?
        public let link: String?
        public let cover: String?
        public let nextPage: String?

        public init(
            path: String? = nil,
            item: String? = nil,
            title: String? = nil,
            link: String? = nil,
            cover: String? = nil,
            nextPage: String? = nil
        ) {
            self.path = path
            self.item = item
            self.title = title
            self.link = link
            self.cover = cover
            self.nextPage = nextPage
        }
    }

    public struct DetailsOverrides: Codable, Sendable, Equatable {
        public let title: String?
        public let cover: String?
        public let synopsis: String?
        public let authors: String?
        public let artists: String?
        public let altTitles: String?
        public let tags: String?
        public let status: String?
        public let contentRating: String?

        public init(
            title: String? = nil,
            cover: String? = nil,
            synopsis: String? = nil,
            authors: String? = nil,
            artists: String? = nil,
            altTitles: String? = nil,
            tags: String? = nil,
            status: String? = nil,
            contentRating: String? = nil
        ) {
            self.title = title
            self.cover = cover
            self.synopsis = synopsis
            self.authors = authors
            self.artists = artists
            self.altTitles = altTitles
            self.tags = tags
            self.status = status
            self.contentRating = contentRating
        }
    }

    public struct ChaptersOverrides: Codable, Sendable, Equatable {
        public let item: String?
        public let link: String?
        public let title: String?
        public let date: String?
        public let order: String?

        public init(
            item: String? = nil, link: String? = nil, title: String? = nil, date: String? = nil, order: String? = nil
        ) {
            self.item = item
            self.link = link
            self.title = title
            self.date = date
            self.order = order
        }
    }

    public struct PagesOverrides: Codable, Sendable, Equatable {
        public let strategies: [ExtractionStrategy]?

        public init(strategies: [ExtractionStrategy]? = nil) {
            self.strategies = strategies
        }
    }

    public struct AttributionOverrides: Codable, Sendable, Equatable {
        public let logo: String?
        public let credits: String?

        public init(logo: String? = nil, credits: String? = nil) {
            self.logo = logo
            self.credits = credits
        }
    }

    public let search: SearchOverrides?
    public let details: DetailsOverrides?
    public let chapters: ChaptersOverrides?
    public let pages: PagesOverrides?
    public let attribution: AttributionOverrides?

    public init(
        search: SearchOverrides? = nil,
        details: DetailsOverrides? = nil,
        chapters: ChaptersOverrides? = nil,
        pages: PagesOverrides? = nil,
        attribution: AttributionOverrides? = nil
    ) {
        self.search = search
        self.details = details
        self.chapters = chapters
        self.pages = pages
        self.attribution = attribution
    }
}

// MARK: - Repository Index Models

/// Repository index format version
public struct RepositoryIndex: Codable, Sendable {
    public let formatVersion: Int
    public let name: String
    public let publicKey: String  // "ed25519:BASE64"
    public let extensions: [ExtensionEntry]

    public init(formatVersion: Int, name: String, publicKey: String, extensions: [ExtensionEntry]) {
        self.formatVersion = formatVersion
        self.name = name
        self.publicKey = publicKey
        self.extensions = extensions
    }
}

public struct ExtensionEntry: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let bundleURL: String
    public let sha256: String
    public let bundleSignature: String

    public init(
        id: String, name: String, version: String, apiVersion: Int, bundleURL: String, sha256: String,
        bundleSignature: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.bundleURL = bundleURL
        self.sha256 = sha256
        self.bundleSignature = bundleSignature
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, apiVersion, bundleURL, sha256, bundleSignature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        bundleURL = try container.decode(String.self, forKey: .bundleURL)
        sha256 = try container.decode(String.self, forKey: .sha256)
        bundleSignature = try container.decode(String.self, forKey: .bundleSignature)

        guard isValidSHA256(sha256) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sha256,
                in: container,
                debugDescription: "sha256 must be 64 hexadecimal characters"
            )
        }

        guard isValidBase64(bundleSignature, byteCount: 64) else {
            throw DecodingError.dataCorruptedError(
                forKey: .bundleSignature,
                in: container,
                debugDescription: "bundleSignature must be a base64-encoded Ed25519 signature"
            )
        }
    }
}

// MARK: - Adapter Manifest

public struct AdapterManifest: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let detectionSignature: ThemeSignature
    public let sha256: String

    public init(
        id: String, name: String, version: String, apiVersion: Int, detectionSignature: ThemeSignature, sha256: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.detectionSignature = detectionSignature
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, apiVersion, detectionSignature, sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        detectionSignature = try container.decode(ThemeSignature.self, forKey: .detectionSignature)
        sha256 = try container.decode(String.self, forKey: .sha256)

        guard apiVersion == PluginEngine.supportedAPIVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .apiVersion,
                in: container,
                debugDescription: "Unsupported API version \(apiVersion); expected \(PluginEngine.supportedAPIVersion)"
            )
        }

        guard isValidSHA256(sha256) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sha256,
                in: container,
                debugDescription: "sha256 must be 64 hexadecimal characters"
            )
        }
    }
}

// MARK: - Validation Helpers

private func isValidSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
}

private func isValidBase64(_ value: String, byteCount: Int) -> Bool {
    guard let data = Data(base64Encoded: value) else { return false }
    return data.count == byteCount
}
