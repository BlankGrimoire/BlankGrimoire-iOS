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
                    return await self.search(profile: profile, query: trimmed)
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
        return url
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

    private func persist(
        details: MangaDetails,
        chapters: [Chapter],
        profile: SiteProfile
    ) async throws -> MangaEntity {
        let identifier = MangaEntity.makeID(siteProfileID: profile.id, key: details.key)
        let manga: MangaEntity
        if let existing = try await mangaRepository.fetchById(identifier) {
            manga = existing
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
        var chaptersByID = Dictionary(uniqueKeysWithValues: existingChapters.map { ($0.id, $0) })

        let imported = chapters.map { chapter -> ChapterEntity in
            let entity = chaptersByID[chapter.key] ?? chapter.makeEntity(manga: manga)
            chapter.apply(to: entity, manga: manga)
            chaptersByID[chapter.key] = entity
            return entity
        }

        if !imported.isEmpty {
            try await chapterRepository.saveAll(imported)
        }

        return manga
    }

    // MARK: - Networking

    private func fetchHTML(_ url: URL, session: AdapterSession) async throws -> String {
        let response = try await session.bridge.request(HttpRequest(url: url.absoluteString))
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
