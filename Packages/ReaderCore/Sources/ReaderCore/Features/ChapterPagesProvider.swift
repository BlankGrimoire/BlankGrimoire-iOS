// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Loads chapter pages through the installed adapter and persists them.
@MainActor
public final class DefaultChapterPagesProvider: ChapterPagesProviding {
    private let pageRepository: any PageRepository
    private let chapterRepository: any ChapterRepository
    private let siteProfileRepository: any SiteProfileRepository
    private let adapterStore: any AdapterStore
    private let logger: any PluginLogger
    private let bridgeFactory: AdapterBridgeFactory
    private let runtimeFactory: AdapterRuntimeFactory

    public convenience init(
        pageRepository: any PageRepository,
        chapterRepository: any ChapterRepository,
        siteProfileRepository: any SiteProfileRepository,
        adapterStore: any AdapterStore,
        logger: any PluginLogger = ConsolePluginLogger()
    ) {
        self.init(
            pageRepository: pageRepository,
            chapterRepository: chapterRepository,
            siteProfileRepository: siteProfileRepository,
            adapterStore: adapterStore,
            logger: logger,
            bridgeFactory: AdapterRuntimeDefaults.makeBridge,
            runtimeFactory: AdapterRuntimeDefaults.makeRuntime
        )
    }

    init(
        pageRepository: any PageRepository,
        chapterRepository: any ChapterRepository,
        siteProfileRepository: any SiteProfileRepository,
        adapterStore: any AdapterStore,
        logger: any PluginLogger,
        bridgeFactory: @escaping AdapterBridgeFactory,
        runtimeFactory: @escaping AdapterRuntimeFactory
    ) {
        self.pageRepository = pageRepository
        self.chapterRepository = chapterRepository
        self.siteProfileRepository = siteProfileRepository
        self.adapterStore = adapterStore
        self.logger = logger
        self.bridgeFactory = bridgeFactory
        self.runtimeFactory = runtimeFactory
    }

    public func pages(for chapter: ChapterEntity, manga: MangaEntity) async throws -> [PageEntity] {
        let cached = try await pageRepository.fetchByChapterId(chapter.id)
        if !cached.isEmpty {
            return cached.sorted { $0.index < $1.index }
        }

        let profile = try await resolveProfile(for: manga)
        let session = try await AdapterSession.open(
            profile: profile,
            adapterStore: adapterStore,
            bridgeFactory: bridgeFactory,
            runtimeFactory: runtimeFactory
        )

        do {
            guard let chapterURL = AdapterSession.absoluteURL(chapter.id, baseURL: profile.baseURL) else {
                throw SiteBrowsingError.invalidSiteURL(chapter.id)
            }
            let response = try await session.bridge.request(HttpRequest(url: chapterURL.absoluteString))
            guard (200...299).contains(response.status) else {
                throw SiteBrowsingError.chapterFetchFailed(response.status)
            }

            let context = PluginPageContext(
                html: response.body,
                baseURL: profile.baseURL,
                siteName: profile.name,
                overrides: profile.selectorOverrides
            )
            let extracted = try await session.runtime.pages(
                mangaKey: manga.adapterKey,
                chapterKey: chapter.id,
                in: context
            )
            guard !extracted.isEmpty else {
                throw SiteBrowsingError.noPages
            }

            let pages =
                extracted
                .sorted { $0.index < $1.index }
                .map { page in
                    PageEntity(
                        id: pageIdentifier(chapterID: chapter.id, index: page.index),
                        index: page.index,
                        imageURL: page.imageURL,
                        headers: page.headers
                    )
                }
            for page in pages {
                page.chapter = chapter
            }

            try await pageRepository.deleteAll(for: chapter.id)
            try await pageRepository.saveAll(pages)

            chapter.pageCount = pages.count
            chapter.updatedAt = Date()
            try await chapterRepository.save(chapter)

            await session.dispose()
            return pages
        } catch {
            await session.dispose()
            throw error
        }
    }

    private func resolveProfile(for manga: MangaEntity) async throws -> SiteProfile {
        if let siteProfileID = manga.siteProfileID,
            let profile = try await siteProfileRepository.fetch(id: siteProfileID)
        {
            return profile
        }

        if let siteURL = manga.siteURL,
            let baseURL = SiteURL.baseURLString(from: siteURL),
            let profile = try await siteProfileRepository.fetchByBaseURL(baseURL)
        {
            return profile
        }

        let profiles = try await siteProfileRepository.fetchAll()
        if let siteURL = manga.siteURL, let host = SiteURL.host(from: siteURL),
            let profile = profiles.first(where: { SiteURL.host(from: $0.baseURL) == host })
        {
            return profile
        }

        if profiles.count == 1, let profile = profiles.first {
            return profile
        }

        throw SiteBrowsingError.siteProfileNotFound(manga.siteProfileID ?? manga.siteURL ?? manga.id)
    }

    private func pageIdentifier(chapterID: String, index: Int) -> String {
        "\(chapterID)::\(index)"
    }
}
