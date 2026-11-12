// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftSoup

/// Default cross-site catalog backed by the installed JavaScript adapters.
@MainActor
public final class SiteCatalogService: SiteCatalogProviding {
    private let siteProfileRepository: any SiteProfileRepository
    private let mangaRepository: any MangaRepository
    private let chapterRepository: any ChapterRepository
    private let adapterStore: any AdapterStore
    private let logger: any PluginLogger
    private let bridgeFactory: AdapterBridgeFactory
    private let runtimeFactory: AdapterRuntimeFactory
    private let sessionPool: AdapterSessionPool

    public convenience init(
        siteProfileRepository: any SiteProfileRepository,
        mangaRepository: any MangaRepository,
        chapterRepository: any ChapterRepository,
        adapterStore: any AdapterStore,
        logger: any PluginLogger = ConsolePluginLogger()
    ) {
        self.init(
            siteProfileRepository: siteProfileRepository,
            mangaRepository: mangaRepository,
            chapterRepository: chapterRepository,
            adapterStore: adapterStore,
            logger: logger,
            bridgeFactory: AdapterRuntimeDefaults.makeBridge,
            runtimeFactory: AdapterRuntimeDefaults.makeRuntime
        )
    }

    init(
        siteProfileRepository: any SiteProfileRepository,
        mangaRepository: any MangaRepository,
        chapterRepository: any ChapterRepository,
        adapterStore: any AdapterStore,
        logger: any PluginLogger,
        bridgeFactory: @escaping AdapterBridgeFactory,
        runtimeFactory: @escaping AdapterRuntimeFactory,
        sessionPool: AdapterSessionPool = AdapterSessionPool()
    ) {
        self.siteProfileRepository = siteProfileRepository
        self.mangaRepository = mangaRepository
        self.chapterRepository = chapterRepository
        self.adapterStore = adapterStore
        self.logger = logger
        self.bridgeFactory = bridgeFactory
        self.runtimeFactory = runtimeFactory
        self.sessionPool = sessionPool
    }

    // MARK: - Search

    public func search(_ query: SearchQuery, in profiles: [SiteProfile]) async -> SiteSearchOutcome {
        await runSearch(query: query, profiles: profiles, startURLs: nil)
    }

    public func searchNextPage(
        query: SearchQuery,
        in profiles: [SiteProfile],
        continuingFrom outcome: SiteSearchOutcome
    ) async -> SiteSearchOutcome {
        let startURLs = outcome.nextPageURLs
        guard !startURLs.isEmpty else {
            return SiteSearchOutcome()
        }
        return await runSearch(query: query, profiles: profiles, startURLs: startURLs)
    }

    /// Shared implementation for the first page and the follow-up pages.
    ///
    /// `startURLs` is nil for the first page: each site's search URL is built
    /// from its theme. For a follow-up page it holds the URL extracted from
    /// each site's own "next" link.
    private func runSearch(
        query: SearchQuery,
        profiles: [SiteProfile],
        startURLs: [String: String]?
    ) async -> SiteSearchOutcome {
        let trimmed = query.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty || !(query.genres?.isEmpty ?? true) else {
            return SiteSearchOutcome()
        }

        let targets: [SiteProfile]
        if let startURLs {
            // Sites that did not announce another page are simply skipped.
            targets = profiles.filter { $0.isEnabled && startURLs[$0.id] != nil }
        } else {
            targets = profiles.filter(\.isEnabled)
        }
        guard !targets.isEmpty else {
            return SiteSearchOutcome()
        }

        var resultsBySite: [String: [SiteSearchResult]] = [:]
        var failures: [SiteSearchFailure] = []
        var nextPageURLs: [String: String] = [:]
        // Opening one JavaScript context per site is expensive; a small window
        // keeps memory bounded when many sites are enabled.
        let maxConcurrent = 3
        let pageNumber = startURLs == nil ? 1 : 2

        await withTaskGroup(of: SiteSearchSiteOutcome.self) { group in
            var remaining = targets.makeIterator()

            for _ in 0..<min(maxConcurrent, targets.count) {
                guard let profile = remaining.next() else { break }
                group.addTask { [weak self] in
                    guard let self else {
                        return .failure(
                            SiteSearchFailure(
                                siteProfileID: profile.id,
                                siteName: profile.name,
                                message: SiteBrowsingError.catalogUnavailable.localizedDescription
                            )
                        )
                    }
                    return await self.searchWithTimeout(
                        profile: profile,
                        query: trimmed,
                        page: pageNumber,
                        startURL: startURLs?[profile.id]
                    )
                }
            }

            while let outcome = await group.next() {
                switch outcome {
                case .success(let siteProfileID, let siteResults, let nextPageURL):
                    resultsBySite[siteProfileID] = siteResults
                    if let nextPageURL {
                        nextPageURLs[siteProfileID] = nextPageURL
                    }
                case .failure(let failure):
                    failures.append(failure)
                }

                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                if let profile = remaining.next() {
                    group.addTask { [weak self] in
                        guard let self else {
                            return .failure(
                                SiteSearchFailure(
                                    siteProfileID: profile.id,
                                    siteName: profile.name,
                                    message: SiteBrowsingError.catalogUnavailable.localizedDescription
                                )
                            )
                        }
                        return await self.searchWithTimeout(
                            profile: profile,
                            query: trimmed,
                            page: pageNumber,
                            startURL: startURLs?[profile.id]
                        )
                    }
                }
            }
        }

        // Adapters occasionally repeat a series in their result list. SwiftUI
        // lists need unique identifiers, and the first occurrence wins.
        var seen = Set<String>()
        // Keep the adapter's relevance order inside each site, and the site
        // order used for the search, instead of re-sorting everything by title.
        let results =
            targets
            .flatMap { resultsBySite[$0.id] ?? [] }
            .filter { seen.insert($0.id).inserted }
        failures.sort { $0.siteName.localizedStandardCompare($1.siteName) == .orderedAscending }

        return SiteSearchOutcome(
            results: results,
            failures: failures,
            nextPageURLs: nextPageURLs
        )
    }

    /// Runs one site search with a hard deadline.
    ///
    /// A site that never answers must not block the cross-site results.
    private func searchWithTimeout(
        profile: SiteProfile,
        query: String,
        page: Int,
        startURL: String?,
        timeout: Duration = .seconds(20)
    ) async -> SiteSearchSiteOutcome {
        await withTaskGroup(of: SiteSearchSiteOutcome?.self) { group in
            group.addTask {
                await self.search(profile: profile, query: query, page: page, startURL: startURL)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()

            return first
                ?? .failure(
                    SiteSearchFailure(
                        siteProfileID: profile.id,
                        siteName: profile.name,
                        message: SiteBrowsingError.searchFailed("Request timed out").localizedDescription
                    )
                )
        }
    }

    private func search(
        profile: SiteProfile,
        query: String,
        page: Int,
        startURL: String?
    ) async -> SiteSearchSiteOutcome {
        do {
            let lease = try await sessionPool.acquire(
                profile: profile,
                adapterStore: adapterStore,
                bridgeFactory: bridgeFactory,
                runtimeFactory: runtimeFactory
            )
            defer { lease.release() }
            let session = lease.session

            let searchURL: URL
            if let startURL, let url = URL(string: startURL) {
                searchURL = url
            } else {
                searchURL = try makeSearchURL(profile: profile, bundle: session.bundle, query: query)
            }
            let html = try await fetchHTML(searchURL, session: session, profile: profile)
            let context = PluginPageContext(
                html: html,
                baseURL: searchURL.absoluteString,
                siteName: profile.name,
                overrides: profile.selectorOverrides
            )
            let resultPage = try await session.runtime.search(
                SearchQuery(text: query, page: page),
                in: context
            )
            let results = resultPage.items.map { summary in
                SiteSearchResult(
                    siteProfileID: profile.id,
                    siteName: profile.name,
                    siteURL: profile.baseURL,
                    key: summary.key,
                    title: summary.title,
                    coverURL: summary.coverURL
                )
            }
            let nextURL = nextPageURL(
                in: html,
                pageURL: searchURL,
                profile: profile,
                bundle: session.bundle
            )
            return .success(
                siteProfileID: profile.id,
                results: results,
                nextPageURL: nextURL?.absoluteString
            )
        } catch {
            logger.error(
                "Search failed for \(profile.name): \(error.localizedDescription)",
                level: 2,
                context: nil
            )
            return .failure(
                SiteSearchFailure(
                    siteProfileID: profile.id,
                    siteName: profile.name,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func makeSearchURL(profile: SiteProfile, bundle: AdapterBundle, query: String) throws -> URL {
        guard let baseURL = URL(string: profile.baseURL) else {
            throw SiteBrowsingError.invalidSiteURL(profile.baseURL)
        }

        let path = profile.selectorOverrides.search?.path ?? bundle.themeAdapter.selectors.search.path
        let encodedQuery =
            query.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(
                    CharacterSet(charactersIn: "&=?#")
                )
            ) ?? query

        if path.contains("{query}") {
            let expanded = path.replacingOccurrences(of: "{query}", with: encodedQuery)
            guard let url = URL(string: expanded, relativeTo: baseURL)?.absoluteURL else {
                throw SiteBrowsingError.invalidSearchURL(path)
            }
            try validateSameSite(url, profile: profile)
            return url
        }

        guard
            var components = URLComponents(
                url: URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL,
                resolvingAgainstBaseURL: false
            )
        else {
            throw SiteBrowsingError.invalidSearchURL(path)
        }

        // Honour a query parameter already present in the search path (for
        // example WordPress' `?s=`), otherwise fall back to the historical `q`.
        var items = components.queryItems ?? []
        let parameterName = items.first { $0.value?.isEmpty != false }?.name ?? "q"
        items.removeAll { $0.name == parameterName }
        items.append(URLQueryItem(name: parameterName, value: query))
        components.queryItems = items
        // URLComponents leaves `+` as-is in query values, but servers decode it
        // as a space; force the percent-encoded form (`C++` -> `C%2B%2B`).
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        guard let url = components.url else {
            throw SiteBrowsingError.invalidSearchURL(path)
        }
        try validateSameSite(url, profile: profile)
        return url
    }

    /// Extracts the URL of the next result page from the current HTML.
    ///
    /// Pagination is driven by the selector declared by the theme, not by a
    /// guessed `?page=` parameter, so it works for sites with any URL scheme.
    private func nextPageURL(
        in html: String,
        pageURL: URL,
        profile: SiteProfile,
        bundle: AdapterBundle
    ) -> URL? {
        let selector =
            profile.selectorOverrides.search?.nextPage
            ?? bundle.themeAdapter.selectors.search.nextPage
        guard let selector, !selector.isEmpty,
            let document = try? SwiftSoup.parse(html),
            let element = try? document.select(selector).first(),
            let href = try? element.attr("href"),
            !href.isEmpty,
            !href.hasPrefix("#"),
            let url = URL(string: href, relativeTo: pageURL)?.absoluteURL
        else {
            return nil
        }

        guard (try? validateSameSite(url, profile: profile)) != nil else {
            return nil
        }
        return url
    }

    /// Search URLs must stay on the site's own host (or a subdomain).
    private func validateSameSite(_ url: URL, profile: SiteProfile) throws {
        guard let host = url.host?.lowercased() else {
            throw SiteBrowsingError.invalidSearchURL(url.absoluteString)
        }
        guard let baseHost = URL(string: profile.baseURL)?.host?.lowercased(), !baseHost.isEmpty else {
            throw SiteBrowsingError.invalidSiteURL(profile.baseURL)
        }
        guard HostMatcher.matches(pattern: baseHost, host: host) else {
            throw SiteBrowsingError.invalidSearchURL(url.absoluteString)
        }
    }

    // MARK: - Import

    public func importManga(_ result: SiteSearchResult) async throws -> MangaEntity {
        guard let profile = try await siteProfileRepository.fetch(id: result.siteProfileID) else {
            throw SiteBrowsingError.siteProfileNotFound(result.siteProfileID)
        }

        let lease = try await sessionPool.acquire(
            profile: profile,
            adapterStore: adapterStore,
            bridgeFactory: bridgeFactory,
            runtimeFactory: runtimeFactory
        )
        defer { lease.release() }
        let session = lease.session

        guard let detailsURL = AdapterSession.absoluteURL(result.key, baseURL: profile.baseURL) else {
            throw SiteBrowsingError.invalidSiteURL(result.key)
        }
        let html = try await fetchHTML(detailsURL, session: session, profile: profile)
        let context = PluginPageContext(
            html: html,
            baseURL: detailsURL.absoluteString,
            siteName: profile.name,
            overrides: profile.selectorOverrides
        )

        let details = try await session.runtime.details(for: result.key, in: context)
        let chapters = try await session.runtime.chapters(for: result.key, in: context)
        let manga = try await persist(details: details, chapters: chapters, profile: profile)
        return manga
    }

    /// Refreshes details and chapter list for an already imported series.
    ///
    /// The local library stays usable when the site is unreachable: the caller
    /// keeps the persisted chapters and reports the network error separately.
    public func refreshChapters(for manga: MangaEntity) async throws {
        guard let profile = try await resolveProfile(for: manga) else {
            throw SiteBrowsingError.siteProfileNotFound(manga.siteProfileID ?? manga.siteURL ?? manga.id)
        }

        let lease = try await sessionPool.acquire(
            profile: profile,
            adapterStore: adapterStore,
            bridgeFactory: bridgeFactory,
            runtimeFactory: runtimeFactory
        )
        defer { lease.release() }
        let session = lease.session

        let key = manga.adapterKey
        guard let detailsURL = AdapterSession.absoluteURL(key, baseURL: profile.baseURL) else {
            throw SiteBrowsingError.invalidSiteURL(key)
        }
        let html = try await fetchHTML(detailsURL, session: session, profile: profile)
        let context = PluginPageContext(
            html: html,
            baseURL: detailsURL.absoluteString,
            siteName: profile.name,
            overrides: profile.selectorOverrides
        )

        let details = try await session.runtime.details(for: key, in: context)
        let chapters = try await session.runtime.chapters(for: key, in: context)
        _ = try await persist(details: details, chapters: chapters, profile: profile, existing: manga)
    }

    /// Finds the site profile that owns a persisted series.
    private func resolveProfile(for manga: MangaEntity) async throws -> SiteProfile? {
        if let siteProfileID = manga.siteProfileID,
            let profile = try await siteProfileRepository.fetch(id: siteProfileID)
        {
            return profile
        }

        guard let siteURL = manga.siteURL, let host = URL(string: siteURL)?.host?.lowercased() else {
            return nil
        }
        let profiles = try await siteProfileRepository.fetchAll()
        return profiles.first { URL(string: $0.baseURL)?.host?.lowercased() == host }
    }

    private func persist(
        details: MangaDetails,
        chapters: [Chapter],
        profile: SiteProfile,
        existing: MangaEntity? = nil
    ) async throws -> MangaEntity {
        let identifier = MangaEntity.makeID(siteProfileID: profile.id, key: details.key)
        let manga: MangaEntity
        if let existing {
            manga = existing
        } else if let stored = try await mangaRepository.fetchById(identifier) {
            manga = stored
        } else {
            manga = details.makeEntity()
            manga.id = identifier
        }

        details.apply(to: manga)
        manga.siteProfileID = profile.id
        manga.siteName = details.attribution?.siteName ?? profile.name
        manga.siteURL =
            sanitizedAttributionURL(details.attribution?.siteURL, profile: profile)
            ?? profile.baseURL
        manga.siteLogoURL = sanitizedAttributionURL(details.attribution?.logoURL, profile: profile)
        manga.siteCredits = details.attribution?.credits
        try await mangaRepository.save(manga)

        let existingChapters = try await chapterRepository.fetchByMangaId(manga.id)
        var chaptersByKey = Dictionary(
            existingChapters.map { ($0.adapterKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var seenKeys = Set<String>()
        let imported = chapters.compactMap { chapter -> ChapterEntity? in
            // Adapters can return the same key twice; keep the first occurrence
            // instead of crashing on a duplicate dictionary key.
            guard seenKeys.insert(chapter.key).inserted else {
                return nil
            }

            let entity =
                chaptersByKey[chapter.key]
                ?? chapter.makeEntity(manga: manga, siteProfileID: profile.id)
            entity.sourceKey = chapter.key
            chapter.apply(to: entity, manga: manga)
            chaptersByKey[chapter.key] = entity
            return entity
        }

        if !imported.isEmpty {
            try await chapterRepository.saveAll(imported)

            // Reconcile chapters that disappeared from the site. Only do this
            // when the adapter returned at least as many chapters as we have:
            // paginated adapters may legitimately return a shorter list.
            if chapters.count >= existingChapters.count {
                let incomingKeys = Set(imported.map(\.adapterKey))
                for stale in existingChapters where !incomingKeys.contains(stale.adapterKey) {
                    try await chapterRepository.delete(stale)
                }
            }
        }

        return manga
    }

    /// Attribution links must stay on the site they describe.
    ///
    /// Adapter-provided URLs are untrusted: an adapter could point the credit
    /// link or logo at an arbitrary host.
    private func sanitizedAttributionURL(_ value: String?, profile: SiteProfile) -> String? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased(),
            let baseHost = URL(string: profile.baseURL)?.host?.lowercased(),
            !baseHost.isEmpty,
            HostMatcher.matches(pattern: baseHost, host: host)
        else {
            return nil
        }
        return url.absoluteString
    }

    // MARK: - Networking

    private func fetchHTML(_ url: URL, session: AdapterSession, profile: SiteProfile) async throws -> String {
        do {
            let response = try await session.bridge.hybridRequest(
                HttpRequest(url: url.absoluteString), siteProfile: profile)
            guard (200...299).contains(response.status) else {
                throw SiteBrowsingError.searchFailed("HTTP \(response.status)")
            }
            return response.body
        } catch let error as PluginEngineError {
            if case .challengeRequired(let challengeURL) = error {
                throw SiteBrowsingError.challengeRequired(challengeURL)
            }
            throw error
        }
    }

    // MARK: - Genre Filtering

    public func fetchGenres(for profile: SiteProfile) async throws -> [SiteGenreFilter] {
        let lease = try await sessionPool.acquire(
            profile: profile,
            adapterStore: adapterStore,
            bridgeFactory: bridgeFactory,
            runtimeFactory: runtimeFactory
        )
        defer { lease.release() }
        let session = lease.session

        guard let genreSelectors = session.bundle.themeAdapter.selectors.genre else {
            return []
        }

        // Convert ThemeSelectors.GenreSelectors to GenreMapping
        let genreMapping = GenreMapping(
            source: genreSelectors.source,
            displayNameAttr: genreSelectors.displayNameAttr,
            valueAttr: genreSelectors.valueAttr,
            valuePattern: genreSelectors.valuePattern,
            filterParam: genreSelectors.filterParam
        )

        let genresURL = try makeGenresURL(profile: profile, bundle: session.bundle)
        let html = try await self.fetchHTML(genresURL, session: session, profile: profile)

        let context = PluginPageContext(
            html: html,
            baseURL: genresURL.absoluteString,
            siteName: profile.name,
            overrides: profile.selectorOverrides
        )

        let result = try await session.runtime.extractGenres(
            mapping: genreMapping,
            in: context
        )
        return result.filters
    }

    public func fetchUnifiedGenres(for profiles: [SiteProfile]) async -> [UnifiedGenre] {
        var genreMap: [String: [String: SiteGenreFilter]] = [:]

        await withTaskGroup(of: (String, [SiteGenreFilter]).self) { group in
            for profile in profiles.filter(\.isEnabled) {
                group.addTask { @Sendable in
                    do {
                        let filters = try await self.fetchGenres(for: profile)
                        return (profile.id, filters)
                    } catch {
                        return (profile.id, [])
                    }
                }
            }

            for await (siteProfileID, filters) in group {
                for filter in filters {
                    let key = filter.displayName.lowercased()
                    genreMap[key, default: [:]][siteProfileID] = filter
                }
            }
        }

        return genreMap.map { (key, siteFilters) in
            UnifiedGenre(
                displayName: siteFilters.values.first?.displayName ?? key.capitalized,
                siteFilters: siteFilters
            )
        }.sorted { $0.displayName < $1.displayName }
    }

    private func makeGenresURL(profile: SiteProfile, bundle: AdapterBundle) throws -> URL {
        let baseURL = URL(string: profile.baseURL)!
        let genrePaths = ["/genre", "/genres", "/genre-list", "/category", "/categories"]

        for path in genrePaths {
            if let url = URL(string: path, relativeTo: baseURL) {
                return url
            }
        }
        return baseURL
    }
}

private enum SiteSearchSiteOutcome: Sendable {
    case success(siteProfileID: String, results: [SiteSearchResult], nextPageURL: String?)
    case failure(SiteSearchFailure)
}
