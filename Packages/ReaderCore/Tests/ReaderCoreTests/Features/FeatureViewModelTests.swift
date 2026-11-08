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
        XCTAssertEqual(viewModel.filteredManga.map(\.id), ["1", "2"])

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
        XCTAssertEqual(repository.profiles.first?.baseURL, "https://example.org")
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
            )
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
