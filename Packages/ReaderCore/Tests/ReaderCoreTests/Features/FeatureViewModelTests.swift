// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testSearchFiltersByTitleAuthorAndTag() async {
        let repository = TestMangaRepository(manga: [
            makeManga(id: "1", title: "Lorem Ipsum", authors: ["Lorem Author"], tags: ["fantasy"]),
            makeManga(id: "2", title: "Dolor Sit", authors: ["Ipsum Author"], tags: ["action"]),
        ])
        let viewModel = LibraryViewModel(mangaRepository: repository)
        await viewModel.loadManga()

        viewModel.searchText = "ipsum"
        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["2", "1"])

        viewModel.searchText = "fantasy"
        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["1"])
    }

    func testFilterOptions() async {
        let inProgress = makeManga(id: "1", title: "Lorem")
        inProgress.readingProgress = 0.5
        let completed = makeManga(id: "2", title: "Dolor")
        completed.readingProgress = 1.0
        let unread = makeManga(id: "3", title: "Sit")
        let favorite = makeManga(id: "4", title: "Amet", isFavorite: true)

        let repository = TestMangaRepository(manga: [inProgress, completed, unread, favorite])
        let viewModel = LibraryViewModel(mangaRepository: repository)
        await viewModel.loadManga()

        viewModel.filterOption = .inProgress
        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["1"])

        viewModel.filterOption = .completed
        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["2"])

        viewModel.filterOption = .unread
        XCTAssertEqual(Set(viewModel.filteredManga.map(\.id)), ["3", "4"])

        viewModel.filterOption = .favorites
        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["4"])
    }

    func testSortByTitle() async {
        let repository = TestMangaRepository(manga: [
            makeManga(id: "1", title: "Zulu"),
            makeManga(id: "2", title: "Alpha"),
        ])
        let viewModel = LibraryViewModel(mangaRepository: repository)
        await viewModel.loadManga()

        viewModel.sortOption = .title
        XCTAssertEqual(viewModel.filteredManga.map(\.title), ["Alpha", "Zulu"])

        viewModel.sortOption = .titleDescending
        XCTAssertEqual(viewModel.filteredManga.map(\.title), ["Zulu", "Alpha"])
    }

    func testUnreadOrderIsStableByTitleAndID() async {
        let repository = TestMangaRepository(manga: [
            makeManga(id: "3", title: "Charlie"),
            makeManga(id: "1", title: "Alpha"),
            makeManga(id: "2", title: "Bravo"),
        ])
        let viewModel = LibraryViewModel(mangaRepository: repository)
        await viewModel.loadManga()

        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["1", "2", "3"])
    }

    func testSearchTextIsTrimmed() async {
        let repository = TestMangaRepository(manga: [makeManga(id: "1", title: "Alpha")])
        let viewModel = LibraryViewModel(mangaRepository: repository)
        await viewModel.loadManga()

        viewModel.searchText = "   "
        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["1"])
    }

    func testDeletingMangaRemovesItFromTheVisibleList() async {
        let manga = makeManga(id: "1", title: "Alpha")
        let repository = TestMangaRepository(manga: [manga])
        let viewModel = LibraryViewModel(mangaRepository: repository)
        await viewModel.loadManga()

        await viewModel.deleteManga(LibraryEntry(entity: manga))

        XCTAssertTrue(viewModel.filteredManga.isEmpty)
        XCTAssertTrue(repository.manga.isEmpty)
    }

    func testTogglingFavoriteUpdatesTheSnapshotAndTheStore() async throws {
        let manga = makeManga(id: "1", title: "Alpha")
        let repository = TestMangaRepository(manga: [manga])
        let viewModel = LibraryViewModel(mangaRepository: repository)
        await viewModel.loadManga()

        let entry = try XCTUnwrap(viewModel.filteredManga.first)
        await viewModel.toggleFavorite(entry)

        XCTAssertEqual(viewModel.filteredManga.first?.isFavorite, true)
        XCTAssertEqual(repository.manga.first?.isFavorite, true)
    }

    private func makeManga(
        id: String,
        title: String,
        authors: [String] = [],
        tags: [String] = [],
        isFavorite: Bool = false
    ) -> MangaEntity {
        MangaEntity(
            id: id,
            title: title,
            authors: authors,
            tags: tags,
            isFavorite: isFavorite
        )
    }
}

@MainActor
final class SitesViewModelTests: XCTestCase {
    func testAddSiteNormalizesURLAndName() async {
        let repository = TestSiteProfileRepository()
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()

        let added = await viewModel.addSite(
            url: "example.org/some/path",
            name: "",
            themeID: "theme.example"
        )

        XCTAssertTrue(added)
        XCTAssertEqual(repository.profiles.first?.baseURL, "https://example.org/some/path")
        XCTAssertEqual(repository.profiles.first?.name, "example.org")
        XCTAssertNil(viewModel.lastError)
    }

    func testAddSiteRejectsInvalidURL() async {
        let repository = TestSiteProfileRepository()
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()

        let added = await viewModel.addSite(
            url: "ftp://example.org",
            name: "Example",
            themeID: "theme.example"
        )

        XCTAssertFalse(added)
        XCTAssertTrue(viewModel.lastError is SiteProfileError)
        XCTAssertTrue(repository.profiles.isEmpty)
    }

    func testAddSiteRejectsDuplicate() async {
        let repository = TestSiteProfileRepository()
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()

        _ = await viewModel.addSite(url: "example.org", name: "One", themeID: "theme.example")
        let second = await viewModel.addSite(url: "https://example.org/", name: "Two", themeID: "theme.example")

        XCTAssertFalse(second)
        XCTAssertEqual(repository.profiles.count, 1)
    }

    func testAddSiteRequiresTheme() async {
        let repository = TestSiteProfileRepository()
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()

        let added = await viewModel.addSite(url: "example.org", name: "Example", themeID: "")

        XCTAssertFalse(added)
        XCTAssertTrue(repository.profiles.isEmpty)
    }

    func testDetectThemeSelectsDetectedTheme() async {
        let repository = TestSiteProfileRepository()
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()
        viewModel.selectedThemeID = "theme.other"

        let result = await viewModel.detectTheme(for: "example.org")

        XCTAssertEqual(result?.theme.id, "theme.example")
        XCTAssertEqual(viewModel.selectedThemeID, "theme.example")
        XCTAssertEqual(viewModel.lastDetection?.theme.id, "theme.example")
    }

    func testSetEnabledPersistsUpdate() async {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.example"
        )
        let repository = TestSiteProfileRepository(profiles: [profile])
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()

        await viewModel.setEnabled(false, for: profile)

        XCTAssertEqual(repository.profiles.first?.isEnabled, false)
    }

    func testSetThemePersistsUpdateAndInstalledVersion() async {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.old"
        )
        let repository = TestSiteProfileRepository(profiles: [profile])
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()

        await viewModel.setTheme("theme.example", for: profile)

        XCTAssertEqual(repository.profiles.first?.themeID, "theme.example")
        XCTAssertEqual(repository.profiles.first?.themeVersion, "1.0.0")
    }

    func testSwitchingBackToTheOriginalThemeIsPersisted() async {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.old",
            themeVersion: "1.0.0"
        )
        let repository = TestSiteProfileRepository(profiles: [profile])
        let viewModel = SitesViewModel(
            siteProfileRepository: repository,
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector()
        )
        await viewModel.loadProfiles()

        await viewModel.setTheme("theme.example", for: profile)
        // The view still holds the original snapshot; switching back must not
        // be treated as a no-op.
        await viewModel.setTheme("theme.old", for: profile)

        XCTAssertEqual(repository.profiles.first?.themeID, "theme.old")
    }

    func testChangingThemeInvalidatesCachedPages() async {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.old"
        )
        let manga = MangaEntity(
            id: "m-1",
            title: "Series",
            siteProfileID: profile.id
        )
        let chapter = ChapterEntity(id: "c-1", number: 1, pageCount: 1)
        chapter.manga = manga
        let pages = RecordingPageRepository()
        let chapters = RecordingChapterRepository(chapters: [chapter])
        let viewModel = SitesViewModel(
            siteProfileRepository: TestSiteProfileRepository(profiles: [profile]),
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector(),
            mangaRepository: TestMangaRepository(manga: [manga]),
            chapterRepository: chapters,
            pageRepository: pages
        )
        await viewModel.loadProfiles()

        await viewModel.setTheme("theme.example", for: profile)

        XCTAssertEqual(pages.deletedChapterIDs, ["c-1"])
        XCTAssertEqual(chapters.downloadStatusUpdates.map(\.chapterID), ["c-1"])
        XCTAssertEqual(chapters.downloadStatusUpdates.map(\.isDownloaded), [false])
    }

    func testChangingToTheSameThemeKeepsCachedPages() async {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.example",
            themeVersion: "1.0.0"
        )
        let manga = MangaEntity(id: "m-1", title: "Series", siteProfileID: profile.id)
        let chapter = ChapterEntity(id: "c-1", number: 1, pageCount: 1)
        chapter.manga = manga
        let pages = RecordingPageRepository()
        let viewModel = SitesViewModel(
            siteProfileRepository: TestSiteProfileRepository(profiles: [profile]),
            themeSource: TestThemeSource(),
            themeDetector: TestThemeDetector(),
            mangaRepository: TestMangaRepository(manga: [manga]),
            chapterRepository: RecordingChapterRepository(chapters: [chapter]),
            pageRepository: pages
        )
        await viewModel.loadProfiles()

        await viewModel.setTheme("theme.example", for: profile)

        XCTAssertTrue(pages.deletedChapterIDs.isEmpty)
    }
}

// MARK: - Test Doubles

@MainActor
private final class TestMangaRepository: MangaRepository {
    var manga: [MangaEntity]

    init(manga: [MangaEntity]) {
        self.manga = manga
    }

    func fetchAll() async throws -> [MangaEntity] { manga }
    func fetchById(_ id: String) async throws -> MangaEntity? { manga.first { $0.id == id } }
    func fetchByIds(_ ids: [String]) async throws -> [MangaEntity] { manga.filter { ids.contains($0.id) } }
    func fetchFavorites() async throws -> [MangaEntity] { manga.filter(\.isFavorite) }
    func fetchRecent(limit: Int) async throws -> [MangaEntity] { Array(manga.prefix(limit)) }
    func fetchByStatus(_ status: MangaStatus) async throws -> [MangaEntity] { manga.filter { $0.status == status } }
    func fetchByTag(_ tag: String) async throws -> [MangaEntity] { manga.filter { $0.tags.contains(tag) } }
    func search(query: String) async throws -> [MangaEntity] {
        manga.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
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
private final class TestSiteProfileRepository: SiteProfileRepository {
    var profiles: [SiteProfile]

    init(profiles: [SiteProfile] = []) {
        self.profiles = profiles
    }

    func fetchAll() async throws -> [SiteProfile] { profiles }
    func fetch(id: String) async throws -> SiteProfile? { profiles.first { $0.id == id } }
    func fetchByBaseURL(_ baseURL: String) async throws -> SiteProfile? {
        profiles.first { $0.baseURL == baseURL }
    }
    func save(_ profile: SiteProfile) async throws {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }
    func delete(_ profile: SiteProfile) async throws {
        profiles.removeAll { $0.id == profile.id }
    }
}

private struct TestThemeSource: ThemeSource {
    func listThemes() async throws -> [ThemeAdapter] {
        [
            ThemeAdapter(
                id: "theme.example",
                name: "Example Theme",
                version: "1.0.0",
                detectionSignature: ThemeSignature(minScore: 1),
                selectors: ThemeSelectors(
                    search: .init(path: "/search", item: ".item", title: ".title", link: "a"),
                    details: .init(title: ".title"),
                    chapters: .init(item: ".chapter", link: "a", order: "desc"),
                    pages: .init(strategies: [])
                )
            ),
            ThemeAdapter(
                id: "theme.old",
                name: "Old Theme",
                version: "1.0.0",
                detectionSignature: ThemeSignature(minScore: 1),
                selectors: ThemeSelectors(
                    search: .init(path: "/search", item: ".item", title: ".title", link: "a"),
                    details: .init(title: ".title"),
                    chapters: .init(item: ".chapter", link: "a", order: "desc"),
                    pages: .init(strategies: [])
                )
            ),
        ]
    }
    func getTheme(id: String) async throws -> ThemeAdapter? { nil }
    func hasTheme(id: String) async throws -> Bool { false }
}

private struct TestThemeDetector: SiteThemeDetecting {
    func detectTheme(for url: String) async throws -> ThemeDetectionResult {
        ThemeDetectionResult(
            theme: ThemeAdapter(
                id: "theme.example",
                name: "Example Theme",
                version: "1.0.0",
                detectionSignature: ThemeSignature(minScore: 1),
                selectors: ThemeSelectors(
                    search: .init(path: "/search", item: ".item", title: ".title", link: "a"),
                    details: .init(title: ".title"),
                    chapters: .init(item: ".chapter", link: "a", order: "desc"),
                    pages: .init(strategies: [])
                )
            ),
            score: 10,
            matchedSignals: ["test"]
        )
    }
}

@MainActor
private final class RecordingPageRepository: PageRepository {
    private(set) var deletedChapterIDs: [String] = []

    func fetchByChapterId(_ chapterId: String) async throws -> [PageEntity] { [] }
    func fetchById(_ id: String) async throws -> PageEntity? { nil }
    func fetchByChapterIdAndIndex(_ chapterId: String, index: Int) async throws -> PageEntity? { nil }
    func save(_ page: PageEntity) async throws {}
    func saveAll(_ pages: [PageEntity]) async throws {}
    func delete(_ page: PageEntity) async throws {}
    func deleteAll(for chapterId: String) async throws {
        deletedChapterIDs.append(chapterId)
    }
    func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws {}
}

@MainActor
private final class RecordingChapterRepository: ChapterRepository {
    private var chapters: [ChapterEntity]
    private(set) var downloadStatusUpdates: [(chapterID: String, isDownloaded: Bool)] = []

    init(chapters: [ChapterEntity]) {
        self.chapters = chapters
    }

    func fetchByMangaId(_ mangaId: String) async throws -> [ChapterEntity] { chapters }
    func fetchById(_ id: String) async throws -> ChapterEntity? { chapters.first { $0.id == id } }
    func fetchByMangaIdAndNumber(_ mangaId: String, number: Double) async throws -> ChapterEntity? { nil }
    func fetchByIds(_ ids: [String]) async throws -> [ChapterEntity] { chapters.filter { ids.contains($0.id) } }
    func fetchDownloadedChapters(for mangaId: String) async throws -> [ChapterEntity] { [] }
    func save(_ chapter: ChapterEntity) async throws {
        if let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
            chapters[index] = chapter
        } else {
            chapters.append(chapter)
        }
    }
    func saveAll(_ chapters: [ChapterEntity]) async throws { self.chapters = chapters }
    func delete(_ chapter: ChapterEntity) async throws {
        chapters.removeAll { $0.id == chapter.id }
    }
    func deleteAll(for mangaId: String) async throws { chapters.removeAll() }
    func updateDownloadStatus(_ chapterId: String, isDownloaded: Bool, downloadedPagesCount: Int) async throws {
        downloadStatusUpdates.append((chapterId, isDownloaded))
    }
}
