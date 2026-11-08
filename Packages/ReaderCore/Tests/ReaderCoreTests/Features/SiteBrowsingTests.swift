// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class SiteCatalogServiceTests: XCTestCase {
    func testSearchAggregatesSitesAndReportsFailures() async {
        let profiles = [
            makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org"),
            makeProfile(id: "site-b", themeID: "theme.b", baseURL: "https://example.com"),
        ]
        let store = TestAdapterStore(bundles: [
            makeBundle(themeID: "theme.a", searchPath: "/search"),
            makeBundle(themeID: "theme.b", searchPath: "/search"),
        ])
        let service = SiteCatalogService(
            siteProfileRepository: TestProfileRepository(profiles: profiles),
            mangaRepository: TestMangaRepository(),
            chapterRepository: TestChapterRepository(),
            adapterStore: store,
            logger: SilentLogger(),
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { bundle, _ in
                TestSiteRuntime(failing: bundle.manifest.id == "theme.b")
            }
        )

        let outcome = await service.search(query: "lorem ipsum", in: profiles)

        XCTAssertEqual(outcome.results.map(\.title), ["Lorem theme.a"])
        XCTAssertEqual(outcome.results.first?.siteProfileID, "site-a")
        XCTAssertEqual(outcome.failures.map(\.siteProfileID), ["site-b"])
    }

    func testSearchSkipsDisabledSitesAndBlankQueries() async {
        let enabled = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")
        var disabled = makeProfile(id: "site-b", themeID: "theme.a", baseURL: "https://example.com")
        disabled.isEnabled = false
        let service = SiteCatalogService(
            siteProfileRepository: TestProfileRepository(profiles: [enabled, disabled]),
            mangaRepository: TestMangaRepository(),
            chapterRepository: TestChapterRepository(),
            adapterStore: TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")]),
            logger: SilentLogger(),
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in TestSiteRuntime() }
        )

        let blank = await service.search(query: "   ", in: [enabled, disabled])
        XCTAssertTrue(blank.results.isEmpty)
        XCTAssertTrue(blank.failures.isEmpty)

        let filtered = await service.search(query: "lorem", in: [enabled, disabled])
        XCTAssertEqual(filtered.results.map(\.siteProfileID), ["site-a"])
    }

    func testImportPersistsDetailsAndChaptersWithoutResettingLocalState() async throws {
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")
        let mangaRepository = TestMangaRepository()
        let chapterRepository = TestChapterRepository()
        let service = SiteCatalogService(
            siteProfileRepository: TestProfileRepository(profiles: [profile]),
            mangaRepository: mangaRepository,
            chapterRepository: chapterRepository,
            adapterStore: TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")]),
            logger: SilentLogger(),
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in TestSiteRuntime() }
        )

        let result = SiteSearchResult(
            siteProfileID: profile.id,
            siteName: profile.name,
            siteURL: profile.baseURL,
            key: "https://example.org/series/lorem",
            title: "Lorem"
        )

        let imported = try await service.importManga(result)

        XCTAssertEqual(imported.id, "site-a::https://example.org/series/lorem")
        XCTAssertEqual(imported.siteProfileID, "site-a")
        XCTAssertEqual(imported.adapterKey, "https://example.org/series/lorem")
        XCTAssertEqual(mangaRepository.manga.count, 1)
        XCTAssertEqual(chapterRepository.chapters.count, 2)

        let chapter = try XCTUnwrap(chapterRepository.chapters.first)
        chapter.pageCount = 12
        chapter.isDownloaded = true

        _ = try await service.importManga(result)

        XCTAssertEqual(mangaRepository.manga.count, 1)
        XCTAssertEqual(chapterRepository.chapters.count, 2)
        XCTAssertEqual(chapter.pageCount, 12)
        XCTAssertTrue(chapter.isDownloaded)
    }
}

@MainActor
final class DefaultChapterPagesProviderTests: XCTestCase {
    func testPagesLoadsFromAdapterAndPersistsThem() async throws {
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")
        let manga = MangaEntity(
            id: MangaEntity.makeID(siteProfileID: profile.id, key: "https://example.org/series/lorem"),
            title: "Lorem",
            siteProfileID: profile.id,
            siteName: profile.name,
            siteURL: profile.baseURL
        )
        let chapter = ChapterEntity(id: "https://example.org/series/lorem/chapter-1", pageCount: 0)
        chapter.manga = manga
        let pageRepository = TestPageRepository()
        let chapterRepository = TestChapterRepository(chapters: [chapter])
        let provider = DefaultChapterPagesProvider(
            pageRepository: pageRepository,
            chapterRepository: chapterRepository,
            siteProfileRepository: TestProfileRepository(profiles: [profile]),
            adapterStore: TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")]),
            logger: SilentLogger(),
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in TestSiteRuntime() }
        )

        let pages = try await provider.pages(for: chapter, manga: manga)

        XCTAssertEqual(pages.map(\.index), [0, 1, 2])
        XCTAssertEqual(pageRepository.pages.count, 3)
        XCTAssertEqual(pageRepository.pages.map(\.index), [0, 1, 2])
        XCTAssertTrue(pageRepository.pages.allSatisfy { $0.chapter === chapter })
        XCTAssertEqual(chapter.pageCount, 3)
    }

    func testPagesUsesCachedPagesWithoutOpeningAnAdapter() async throws {
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")
        let manga = MangaEntity(
            id: "manga",
            title: "Lorem",
            siteProfileID: profile.id,
            siteURL: profile.baseURL
        )
        let chapter = ChapterEntity(id: "chapter", pageCount: 1)
        let cached = PageEntity(index: 0, imageURL: "https://example.org/cached.jpg")
        cached.chapter = chapter
        let pageRepository = TestPageRepository(pages: [cached])
        let provider = DefaultChapterPagesProvider(
            pageRepository: pageRepository,
            chapterRepository: TestChapterRepository(chapters: [chapter]),
            siteProfileRepository: TestProfileRepository(profiles: [profile]),
            adapterStore: TestAdapterStore(bundles: []),
            logger: SilentLogger(),
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in TestSiteRuntime() }
        )

        let pages = try await provider.pages(for: chapter, manga: manga)

        XCTAssertEqual(pages.map(\.id), [cached.id])
    }

    func testPagesRejectsMissingProfile() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter")
        let provider = DefaultChapterPagesProvider(
            pageRepository: TestPageRepository(),
            chapterRepository: TestChapterRepository(),
            siteProfileRepository: TestProfileRepository(profiles: []),
            adapterStore: TestAdapterStore(bundles: []),
            logger: SilentLogger(),
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in TestSiteRuntime() }
        )

        do {
            _ = try await provider.pages(for: chapter, manga: manga)
            XCTFail("Expected a missing site profile error")
        } catch let error as SiteBrowsingError {
            XCTAssertEqual(error, .siteProfileNotFound("manga"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Fixtures

@MainActor
private func makeProfile(id: String, themeID: String, baseURL: String) -> SiteProfile {
    SiteProfile(id: id, name: id, baseURL: baseURL, themeID: themeID)
}

private func makeBundle(themeID: String, searchPath: String) -> AdapterBundle {
    let selectors = ThemeSelectors(
        search: .init(path: searchPath, item: ".item", title: ".title", link: "a"),
        details: .init(title: ".title"),
        chapters: .init(item: ".chapter", link: "a", order: "desc"),
        pages: .init(strategies: [])
    )
    let signature = ThemeSignature(minScore: 1)
    let theme = ThemeAdapter(
        id: themeID,
        name: themeID,
        version: "1.0.0",
        detectionSignature: signature,
        selectors: selectors
    )
    let manifest = AdapterManifest(
        id: themeID,
        name: themeID,
        version: "1.0.0",
        apiVersion: ContractVersion.current,
        detectionSignature: signature,
        sha256: "00"
    )
    return AdapterBundle(
        manifest: manifest,
        themeAdapter: theme,
        bundleData: Data(),
        sourceRepositoryURL: "https://example.org/index.json"
    )
}

private func makeBridgeFactory() -> AdapterBridgeFactory {
    { profile in
        PluginBridge(
            policy: profile.makeNetworkPolicy(),
            logger: SilentLogger(),
            customRequestHandler: { request in
                HttpResponse(status: 200, url: request.url, headers: [:], body: "<html></html>")
            }
        )
    }
}

private struct SilentLogger: PluginLogger {
    func log(_ message: String, level: Int, context: [String: Any]?) {}
    func error(_ message: String, level: Int, context: [String: Any]?) {}
    func warn(_ message: String, level: Int, context: [String: Any]?) {}
}

// MARK: - Runtime Double

private struct TestSiteRuntime: SiteAdapterRuntime {
    var failing = false

    func search(_ query: SearchQuery, in page: PluginPageContext) async throws -> PagedResult<MangaSummary> {
        if failing {
            throw SiteBrowsingError.searchFailed("boom")
        }
        return PagedResult(
            items: [MangaSummary(key: "https://example.org/\(title)", title: title)],
            hasNextPage: false
        )
    }

    func details(for key: String, in page: PluginPageContext) async throws -> MangaDetails {
        MangaDetails(
            key: key,
            title: "Lorem",
            authors: ["Lorem Author"],
            synopsis: "Dolor sit amet",
            tags: ["fantasy"],
            status: .ongoing,
            contentRating: .safe,
            attribution: Attribution(siteName: "Example Site", siteURL: "https://example.org")
        )
    }

    func chapters(for key: String, in page: PluginPageContext) async throws -> [Chapter] {
        [
            Chapter(key: "\(key)/chapter-1", title: "Chapter 1", number: 1),
            Chapter(key: "\(key)/chapter-2", title: "Chapter 2", number: 2),
        ]
    }

    func pages(mangaKey: String, chapterKey: String, in page: PluginPageContext) async throws -> [Page] {
        [
            Page(index: 2, imageURL: "https://example.org/page-3.jpg"),
            Page(index: 0, imageURL: "https://example.org/page-1.jpg", headers: ["Referer": "https://example.org"]),
            Page(index: 1, imageURL: "https://example.org/page-2.jpg"),
        ]
    }

    func dispose() async {}

    private var title: String {
        "Lorem theme.a"
    }
}

// MARK: - Repository Doubles

@MainActor
private final class TestAdapterStore: AdapterStore {
    let bundles: [AdapterBundle]

    init(bundles: [AdapterBundle]) {
        self.bundles = bundles
    }

    func fetchRepositoryIndex(from url: String) async throws -> RepositoryIndex {
        RepositoryIndex(formatVersion: 1, name: "Example", publicKey: "ed25519:test", extensions: [])
    }
    func trustRepository(_ index: RepositoryIndex) async throws {}
    func isRepositoryTrusted(_ url: String) async throws -> Bool { true }
    func listTrustedRepositories() async throws -> [TrustedRepository] { [] }
    func removeTrust(for url: String) async throws {}
    func installAdapter(id: String, version: String, from repositoryURL: String) async throws -> AdapterBundle {
        try XCTUnwrap(bundles.first { $0.manifest.id == id })
    }
    func uninstallAdapter(id: String) async throws {}
    func listInstalledAdapters() async throws -> [AdapterBundle] { bundles }
    func getInstalledAdapter(id: String) async throws -> AdapterBundle? {
        bundles.first { $0.manifest.id == id }
    }
    func checkForUpdates() async throws -> [(adapter: AdapterBundle, update: ExtensionEntry)] { [] }
    func updateAdapter(id: String, to version: String) async throws -> AdapterBundle {
        try XCTUnwrap(bundles.first { $0.manifest.id == id })
    }
}

@MainActor
private final class TestProfileRepository: SiteProfileRepository {
    var profiles: [SiteProfile]

    init(profiles: [SiteProfile]) {
        self.profiles = profiles
    }

    func fetchAll() async throws -> [SiteProfile] { profiles }
    func fetch(id: String) async throws -> SiteProfile? { profiles.first { $0.id == id } }
    func fetchByBaseURL(_ baseURL: String) async throws -> SiteProfile? {
        profiles.first { $0.baseURL == baseURL }
    }
    func save(_ profile: SiteProfile) async throws {}
    func delete(_ profile: SiteProfile) async throws {}
}

@MainActor
private final class TestMangaRepository: MangaRepository {
    var manga: [MangaEntity] = []

    func fetchAll() async throws -> [MangaEntity] { manga }
    func fetchById(_ id: String) async throws -> MangaEntity? { manga.first { $0.id == id } }
    func fetchByIds(_ ids: [String]) async throws -> [MangaEntity] { manga.filter { ids.contains($0.id) } }
    func fetchFavorites() async throws -> [MangaEntity] { [] }
    func fetchRecent(limit: Int) async throws -> [MangaEntity] { Array(manga.prefix(limit)) }
    func fetchByStatus(_ status: MangaStatus) async throws -> [MangaEntity] { [] }
    func fetchByTag(_ tag: String) async throws -> [MangaEntity] { [] }
    func search(query: String) async throws -> [MangaEntity] { [] }
    func save(_ manga: MangaEntity) async throws {
        if let index = self.manga.firstIndex(where: { $0.id == manga.id }) {
            self.manga[index] = manga
        } else {
            self.manga.append(manga)
        }
    }
    func delete(_ manga: MangaEntity) async throws { self.manga.removeAll { $0.id == manga.id } }
    func deleteAll() async throws { manga.removeAll() }
    func count() async throws -> Int { manga.count }
}

@MainActor
private final class TestChapterRepository: ChapterRepository {
    var chapters: [ChapterEntity]

    init(chapters: [ChapterEntity] = []) {
        self.chapters = chapters
    }

    func fetchByMangaId(_ mangaId: String) async throws -> [ChapterEntity] {
        chapters.filter { $0.manga?.id == mangaId }
    }
    func fetchById(_ id: String) async throws -> ChapterEntity? { chapters.first { $0.id == id } }
    func fetchByMangaIdAndNumber(_ mangaId: String, number: Double) async throws -> ChapterEntity? {
        chapters.first { $0.manga?.id == mangaId && $0.number == number }
    }
    func fetchByIds(_ ids: [String]) async throws -> [ChapterEntity] { chapters.filter { ids.contains($0.id) } }
    func fetchDownloadedChapters(for mangaId: String) async throws -> [ChapterEntity] { [] }
    func save(_ chapter: ChapterEntity) async throws {
        if let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
            chapters[index] = chapter
        } else {
            chapters.append(chapter)
        }
    }
    func saveAll(_ chapters: [ChapterEntity]) async throws {
        for chapter in chapters {
            try await save(chapter)
        }
    }
    func delete(_ chapter: ChapterEntity) async throws { chapters.removeAll { $0.id == chapter.id } }
    func deleteAll(for mangaId: String) async throws { chapters.removeAll { $0.manga?.id == mangaId } }
    func updateDownloadStatus(
        _ chapterId: String,
        isDownloaded: Bool,
        downloadedPagesCount: Int
    ) async throws {}
}

@MainActor
private final class TestPageRepository: PageRepository {
    var pages: [PageEntity]

    init(pages: [PageEntity] = []) {
        self.pages = pages
    }

    func fetchByChapterId(_ chapterId: String) async throws -> [PageEntity] {
        pages.filter { $0.chapter?.id == chapterId }
    }
    func fetchById(_ id: String) async throws -> PageEntity? { pages.first { $0.id == id } }
    func fetchByChapterIdAndIndex(_ chapterId: String, index: Int) async throws -> PageEntity? {
        pages.first { $0.chapter?.id == chapterId && $0.index == index }
    }
    func save(_ page: PageEntity) async throws {
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            pages[index] = page
        } else {
            pages.append(page)
        }
    }
    func saveAll(_ pages: [PageEntity]) async throws {
        for page in pages {
            try await save(page)
        }
    }
    func delete(_ page: PageEntity) async throws { pages.removeAll { $0.id == page.id } }
    func deleteAll(for chapterId: String) async throws {
        pages.removeAll { $0.chapter?.id == chapterId }
    }
    func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws {}
}
