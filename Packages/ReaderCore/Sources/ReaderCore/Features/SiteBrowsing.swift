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
    /// Next result page per site, keyed by `siteProfileID`.
    ///
    /// The catalog extracts the URL from each site's own pagination selector,
    /// so the caller only has to hand these back to `searchNextPage`.
    public let nextPageURLs: [String: String]

    /// Whether at least one site has another result page.
    public var hasMore: Bool { !nextPageURLs.isEmpty }

    public init(
        results: [SiteSearchResult] = [],
        failures: [SiteSearchFailure] = [],
        nextPageURLs: [String: String] = [:]
    ) {
        self.results = results
        self.failures = failures
        self.nextPageURLs = nextPageURLs
    }
}

/// Cross-site catalog operations used by the browse screen.
@MainActor
public protocol SiteCatalogProviding: Sendable {
    func search(_ query: SearchQuery, in profiles: [SiteProfile]) async -> SiteSearchOutcome
    /// Loads the next result page for the sites that announced one.
    ///
    /// Pass the previous outcome: implementations use its `nextPageURLs` to
    /// fetch the following page without repeating the earlier requests.
    func searchNextPage(
        query: SearchQuery,
        in profiles: [SiteProfile],
        continuingFrom outcome: SiteSearchOutcome
    ) async -> SiteSearchOutcome
    func importManga(_ result: SiteSearchResult) async throws -> MangaEntity
    /// Refreshes details and chapters for an imported series from its site.
    func refreshChapters(for manga: MangaEntity) async throws
    /// Extracts the list of genre filters available on a site.
    func fetchGenres(for profile: SiteProfile) async throws -> [SiteGenreFilter]
    /// Extracts and unifies genres across multiple sites (case-insensitive merge).
    func fetchUnifiedGenres(for profiles: [SiteProfile]) async -> [UnifiedGenre]
}

extension SiteCatalogProviding {
    /// Catalogs that do not paginate report that no further page exists.
    public func searchNextPage(
        query: SearchQuery,
        in profiles: [SiteProfile],
        continuingFrom outcome: SiteSearchOutcome
    ) async -> SiteSearchOutcome {
        SiteSearchOutcome()
    }

    public func fetchGenres(for profile: SiteProfile) async throws -> [SiteGenreFilter] {
        throw SiteBrowsingError.catalogUnavailable
    }

    public func fetchUnifiedGenres(for profiles: [SiteProfile]) async -> [UnifiedGenre] {
        // Default implementation returns empty array - conforming types should override
        return []
    }
}

/// Loads the pages of a chapter through its installed adapter.
@MainActor
public protocol ChapterPagesProviding: Sendable {
    /// Loads the pages, optionally ignoring a cached copy.
    ///
    /// Adapters can emit signed image URLs that expire, so callers must be
    /// able to ask for a fresh set after a failed load or a completed challenge.
    func pages(
        for chapter: ChapterEntity,
        manga: MangaEntity,
        forceRefresh: Bool
    ) async throws -> [PageEntity]
}

extension ChapterPagesProviding {
    /// Convenience overload that uses the cache when it is still valid.
    public func pages(for chapter: ChapterEntity, manga: MangaEntity) async throws -> [PageEntity] {
        try await pages(for: chapter, manga: manga, forceRefresh: false)
    }
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
    case duplicatePageIndex(Int)
    case invalidPageURL(String)
    case challengeRequired(URL)
    case catalogUnavailable

    /// User-facing text comes from `Localizable.xcstrings` in this module so
    /// it can be translated without touching the error type.
    public var errorDescription: String? {
        switch self {
        case .adapterNotInstalled(let id):
            return String(
                localized: "site.error.adapterNotInstalled",
                defaultValue: "No installed adapter named \(id). Install it from Settings → Adapters.",
                bundle: .module,
                comment: "No adapter with this identifier is installed."
            )
        case .siteProfileNotFound(let id):
            return String(
                localized: "site.error.siteProfileNotFound",
                defaultValue: "Site profile not found: \(id)",
                bundle: .module,
                comment: "The requested site profile no longer exists."
            )
        case .invalidSiteURL(let url):
            return String(
                localized: "site.error.invalidSiteURL",
                defaultValue: "Invalid site URL: \(url)",
                bundle: .module,
                comment: "The configured site URL is not a valid HTTPS URL."
            )
        case .invalidSearchURL(let url):
            return String(
                localized: "site.error.invalidSearchURL",
                defaultValue: "Unable to build a search URL for \(url)",
                bundle: .module,
                comment: "The search path could not be turned into a URL."
            )
        case .searchFailed(let message):
            return String(
                localized: "site.error.searchFailed",
                defaultValue: "Search failed: \(message)",
                bundle: .module,
                comment: "A site search failed with a diagnostic message."
            )
        case .chapterFetchFailed(let status):
            return String(
                localized: "site.error.chapterFetchFailed",
                defaultValue: "The chapter page returned HTTP \(status)",
                bundle: .module,
                comment: "The chapter request returned a non-success HTTP status."
            )
        case .noPages:
            return String(
                localized: "site.error.noPages",
                defaultValue: "The adapter returned no pages for this chapter",
                bundle: .module,
                comment: "The adapter returned an empty page list."
            )
        case .duplicatePageIndex(let index):
            return String(
                localized: "site.error.duplicatePageIndex",
                defaultValue: "The adapter returned duplicate page index \(index)",
                bundle: .module,
                comment: "The adapter returned two pages with the same index."
            )
        case .invalidPageURL(let url):
            return String(
                localized: "site.error.invalidPageURL",
                defaultValue: "The adapter returned an invalid page URL: \(url)",
                bundle: .module,
                comment: "The adapter returned a page URL the app refuses to load."
            )
        case .challengeRequired(let url):
            return String(
                localized: "site.error.challengeRequired",
                defaultValue: "The site requires a verification before continuing: \(url.absoluteString)",
                bundle: .module,
                comment: "The site asks the user to complete a verification page."
            )
        case .catalogUnavailable:
            return String(
                localized: "site.error.catalogUnavailable",
                defaultValue: "Site browsing is unavailable",
                bundle: .module,
                comment: "Cross-site browsing is not configured."
            )
        }
    }
}
