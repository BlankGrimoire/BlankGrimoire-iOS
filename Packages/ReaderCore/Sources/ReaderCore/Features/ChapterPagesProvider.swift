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
            let chapterKey = chapter.adapterKey
            guard let chapterURL = AdapterSession.absoluteURL(chapterKey, baseURL: profile.baseURL) else {
                throw SiteBrowsingError.invalidSiteURL(chapterKey)
            }
            let response = try await session.bridge.request(HttpRequest(url: chapterURL.absoluteString))
            if response.status == 403 || response.status == 503 {
                throw SiteBrowsingError.challengeRequired(chapterURL)
            }
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
                chapterKey: chapterKey,
                in: context
            )
            guard !extracted.isEmpty else {
                throw SiteBrowsingError.noPages
            }

            let pages = try validatedPages(extracted, chapter: chapter, profile: profile)
            for page in pages {
                page.chapter = chapter
            }

            try await pageRepository.replaceAll(for: chapter.id, with: pages)

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

    /// Validates adapter output before it reaches persistence or the network.
    private func validatedPages(
        _ extracted: [Page],
        chapter: ChapterEntity,
        profile: SiteProfile
    ) throws -> [PageEntity] {
        guard let baseHost = URL(string: profile.baseURL)?.host?.lowercased(), !baseHost.isEmpty else {
            throw SiteBrowsingError.invalidSiteURL(profile.baseURL)
        }

        var seenIndices = Set<Int>()
        var pages: [PageEntity] = []

        for page in extracted {
            guard seenIndices.insert(page.index).inserted else {
                throw SiteBrowsingError.duplicatePageIndex(page.index)
            }

            guard
                let url = URL(string: page.imageURL),
                url.scheme?.lowercased() == "https",
                let host = url.host?.lowercased(),
                HostMatcher.matches(pattern: baseHost, host: host)
            else {
                throw SiteBrowsingError.invalidPageURL(page.imageURL)
            }

            pages.append(
                PageEntity(
                    id: pageIdentifier(chapterID: chapter.id, index: page.index),
                    index: page.index,
                    imageURL: page.imageURL,
                    headers: Self.sanitizedHeaders(page.headers)
                )
            )
        }

        return pages.sorted { $0.index < $1.index }
    }

    /// Removes headers that must be controlled by the native request layer.
    private static func sanitizedHeaders(_ headers: [String: String]?) -> [String: String]? {
        guard let headers else { return nil }
        let reserved: Set<String> = ["host", "cookie", "authorization", "proxy-authorization"]
        let sanitized = headers.filter { !reserved.contains($0.key.lowercased()) }
        return sanitized.isEmpty ? nil : sanitized
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
        if let siteURL = manga.siteURL,
            let host = SiteURL.host(from: siteURL),
            let profile = profiles.first(where: { SiteURL.host(from: $0.baseURL) == host })
        {
            return profile
        }

        throw SiteBrowsingError.siteProfileNotFound(manga.siteProfileID ?? manga.siteURL ?? manga.id)
    }

    private func pageIdentifier(chapterID: String, index: Int) -> String {
        "\(chapterID)::\(index)"
    }
}
