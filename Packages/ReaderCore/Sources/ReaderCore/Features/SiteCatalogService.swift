// SPDX-License-Identifier: MPL-2.0

import Foundation

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
        runtimeFactory: @escaping AdapterRuntimeFactory
    ) {
        self.siteProfileRepository = siteProfileRepository
        self.mangaRepository = mangaRepository
        self.chapterRepository = chapterRepository
        self.adapterStore = adapterStore
        self.logger = logger
        self.bridgeFactory = bridgeFactory
        self.runtimeFactory = runtimeFactory
    }

    // MARK: - Search

    public func search(query: String, in profiles: [SiteProfile]) async -> SiteSearchOutcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SiteSearchOutcome()
        }

        let targets = profiles.filter(\.isEnabled)
        guard !targets.isEmpty else {
            return SiteSearchOutcome()
        }

        var results: [SiteSearchResult] = []
        var failures: [SiteSearchFailure] = []

        await withTaskGroup(of: SiteSearchSiteOutcome.self) { group in
            for profile in targets {
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
                    return await self.searchWithTimeout(profile: profile, query: trimmed)
                }
            }

            for await outcome in group {
                switch outcome {
                case .success(let siteResults):
                    results.append(contentsOf: siteResults)
                case .failure(let failure):
                    failures.append(failure)
                }
            }
        }

        results.sort {
            let comparison = $0.title.localizedStandardCompare($1.title)
            if comparison == .orderedSame {
                return $0.siteName.localizedStandardCompare($1.siteName) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
        failures.sort { $0.siteName.localizedStandardCompare($1.siteName) == .orderedAscending }

        return SiteSearchOutcome(results: results, failures: failures)
    }

    /// Runs one site search with a hard deadline.
    ///
    /// A site that never answers must not block the cross-site results.
    private func searchWithTimeout(
        profile: SiteProfile,
        query: String,
        timeout: Duration = .seconds(20)
    ) async -> SiteSearchSiteOutcome {
        await withTaskGroup(of: SiteSearchSiteOutcome?.self) { group in
            group.addTask {
                await self.search(profile: profile, query: query)
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

    private func search(profile: SiteProfile, query: String) async -> SiteSearchSiteOutcome {
        do {
            let session = try await AdapterSession.open(
                profile: profile,
                adapterStore: adapterStore,
                bridgeFactory: bridgeFactory,
                runtimeFactory: runtimeFactory
            )

            do {
                let searchURL = try makeSearchURL(profile: profile, bundle: session.bundle, query: query)
                let html = try await fetchHTML(searchURL, session: session)
                let context = PluginPageContext(
                    html: html,
                    baseURL: profile.baseURL,
                    siteName: profile.name,
                    overrides: profile.selectorOverrides
                )
                let page = try await session.runtime.search(
                    SearchQuery(text: query, page: 1),
                    in: context
                )
                let results = page.items.map { summary in
                    SiteSearchResult(
                        siteProfileID: profile.id,
                        siteName: profile.name,
                        siteURL: profile.baseURL,
                        key: summary.key,
                        title: summary.title,
                        coverURL: summary.coverURL
                    )
                }
                await session.dispose()
                return .success(results)
            } catch {
                await session.dispose()
                throw error
            }
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

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "q" }
        items.append(URLQueryItem(name: "q", value: query))
        components.queryItems = items

        guard let url = components.url else {
            throw SiteBrowsingError.invalidSearchURL(path)
        }
        try validateSameSite(url, profile: profile)
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

        let session = try await AdapterSession.open(
            profile: profile,
            adapterStore: adapterStore,
            bridgeFactory: bridgeFactory,
            runtimeFactory: runtimeFactory
        )

        do {
            guard let detailsURL = AdapterSession.absoluteURL(result.key, baseURL: profile.baseURL) else {
                throw SiteBrowsingError.invalidSiteURL(result.key)
            }
            let html = try await fetchHTML(detailsURL, session: session)
            let context = PluginPageContext(
                html: html,
                baseURL: profile.baseURL,
                siteName: profile.name,
                overrides: profile.selectorOverrides
            )

            let details = try await session.runtime.details(for: result.key, in: context)
            let chapters = try await session.runtime.chapters(for: result.key, in: context)
            let manga = try await persist(details: details, chapters: chapters, profile: profile)
            await session.dispose()
            return manga
        } catch {
            await session.dispose()
            throw error
        }
    }

    /// Refreshes details and chapter list for an already imported series.
    ///
    /// The local library stays usable when the site is unreachable: the caller
    /// keeps the persisted chapters and reports the network error separately.
    public func refreshChapters(for manga: MangaEntity) async throws {
        guard let profile = try await resolveProfile(for: manga) else {
            throw SiteBrowsingError.siteProfileNotFound(manga.siteProfileID ?? manga.siteURL ?? manga.id)
        }

        let session = try await AdapterSession.open(
            profile: profile,
            adapterStore: adapterStore,
            bridgeFactory: bridgeFactory,
            runtimeFactory: runtimeFactory
        )

        do {
            let key = manga.adapterKey
            guard let detailsURL = AdapterSession.absoluteURL(key, baseURL: profile.baseURL) else {
                throw SiteBrowsingError.invalidSiteURL(key)
            }
            let html = try await fetchHTML(detailsURL, session: session)
            let context = PluginPageContext(
                html: html,
                baseURL: profile.baseURL,
                siteName: profile.name,
                overrides: profile.selectorOverrides
            )

            let details = try await session.runtime.details(for: key, in: context)
            let chapters = try await session.runtime.chapters(for: key, in: context)
            _ = try await persist(details: details, chapters: chapters, profile: profile, existing: manga)
            await session.dispose()
        } catch {
            await session.dispose()
            throw error
        }
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
        manga.siteURL = details.attribution?.siteURL ?? profile.baseURL
        manga.siteLogoURL = details.attribution?.logoURL
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

    // MARK: - Networking

    private func fetchHTML(_ url: URL, session: AdapterSession) async throws -> String {
        let response = try await session.bridge.request(HttpRequest(url: url.absoluteString))
        if response.status == 403 || response.status == 503 {
            throw SiteBrowsingError.challengeRequired(url)
        }
        guard (200...299).contains(response.status) else {
            throw SiteBrowsingError.searchFailed("HTTP \(response.status)")
        }
        return response.body
    }
}

private enum SiteSearchSiteOutcome: Sendable {
    case success([SiteSearchResult])
    case failure(SiteSearchFailure)
}
