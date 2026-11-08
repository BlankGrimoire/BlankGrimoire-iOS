// SPDX-License-Identifier: MPL-2.0

import Foundation

/// One search hit coming from a configured site profile.
public struct SiteSearchResult: Identifiable, Sendable, Equatable {
    public let siteProfileID: String
    public let siteName: String
    public let siteURL: String
    public let key: String
    public let title: String
    public let coverURL: String?

    public var id: String {
        "\(siteProfileID)::\(key)"
    }

    public init(
        siteProfileID: String,
        siteName: String,
        siteURL: String,
        key: String,
        title: String,
        coverURL: String? = nil
    ) {
        self.siteProfileID = siteProfileID
        self.siteName = siteName
        self.siteURL = siteURL
        self.key = key
        self.title = title
        self.coverURL = coverURL
    }
}

/// A site that could not answer a search request.
public struct SiteSearchFailure: Identifiable, Sendable, Equatable {
    public let siteProfileID: String
    public let siteName: String
    public let message: String

    public var id: String { siteProfileID }

    public init(siteProfileID: String, siteName: String, message: String) {
        self.siteProfileID = siteProfileID
        self.siteName = siteName
        self.message = message
    }
}

/// Aggregated result of a cross-site search.
public struct SiteSearchOutcome: Sendable, Equatable {
    public let results: [SiteSearchResult]
    public let failures: [SiteSearchFailure]

    public init(results: [SiteSearchResult] = [], failures: [SiteSearchFailure] = []) {
        self.results = results
        self.failures = failures
    }
}

/// Cross-site catalog operations used by the browse screen.
@MainActor
public protocol SiteCatalogProviding: Sendable {
    func search(query: String, in profiles: [SiteProfile]) async -> SiteSearchOutcome
    func importManga(_ result: SiteSearchResult) async throws -> MangaEntity
}

/// Loads the pages of a chapter through its installed adapter.
@MainActor
public protocol ChapterPagesProviding: Sendable {
    func pages(for chapter: ChapterEntity, manga: MangaEntity) async throws -> [PageEntity]
}

/// Errors surfaced by site browsing and page loading.
public enum SiteBrowsingError: Error, LocalizedError, Sendable, Equatable {
    case adapterNotInstalled(String)
    case siteProfileNotFound(String)
    case invalidSiteURL(String)
    case invalidSearchURL(String)
    case searchFailed(String)
    case chapterFetchFailed(Int)
    case noPages
    case catalogUnavailable

    public var errorDescription: String? {
        switch self {
        case .adapterNotInstalled(let id):
            return "No installed adapter named \(id). Install it from Settings → Adapters."
        case .siteProfileNotFound(let id):
            return "Site profile not found: \(id)"
        case .invalidSiteURL(let url):
            return "Invalid site URL: \(url)"
        case .invalidSearchURL(let url):
            return "Unable to build a search URL for \(url)"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        case .chapterFetchFailed(let status):
            return "The chapter page returned HTTP \(status)"
        case .noPages:
            return "The adapter returned no pages for this chapter"
        case .catalogUnavailable:
            return "Site browsing is unavailable"
        }
    }
}
