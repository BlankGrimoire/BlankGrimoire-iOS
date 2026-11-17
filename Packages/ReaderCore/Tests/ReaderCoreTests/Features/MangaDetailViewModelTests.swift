// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class MangaDetailViewModelTests: XCTestCase {
    func testLoadChaptersSortsNumericOrderWithUnnumberedLast() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let chapters = [
            ChapterEntity(id: "c-unknown", title: "Extra", number: nil, pageCount: 1),
            ChapterEntity(id: "c-10", number: 10, pageCount: 1),
            ChapterEntity(id: "c-2", number: 2, pageCount: 1),
            ChapterEntity(id: "c-1", number: 1, pageCount: 1),
        ]
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: chapters),
            mangaRepository: StubMangaRepository(manga: manga)
        )

        await viewModel.loadChapters()

        XCTAssertEqual(viewModel.chapters.map(\.id), ["c-1", "c-2", "c-10", "c-unknown"])
        XCTAssertFalse(viewModel.isLoadingChapters)
    }

    func testReadChapterKeepsFirstPagePosition() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let chapter = ChapterEntity(id: "c-1", number: 1, pageCount: 20)
        let repository = StubMangaRepository(manga: manga)
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: [chapter]),
            mangaRepository: repository
        )

        await viewModel.readChapter(chapter)

        XCTAssertEqual(manga.lastReadChapterId, "c-1")
        XCTAssertEqual(manga.lastReadPageIndex, 0)
        XCTAssertGreaterThan(manga.readingProgress, 0)
        XCTAssertEqual(repository.saveCount, 1)
    }

    func testReadChapterUsesOnePageForEmptyChapter() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let chapter = ChapterEntity(id: "c-1", number: 1, pageCount: 0)
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: [chapter]),
            mangaRepository: StubMangaRepository(manga: manga)
        )

        await viewModel.readChapter(chapter)

        XCTAssertEqual(manga.lastReadPageIndex, 0)
        XCTAssertEqual(manga.readingProgress, 1.0, accuracy: 0.0001)
    }

    func testMarkAllAsReadLoadsChaptersAndCompletesLastOne() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let chapters = [
            ChapterEntity(id: "c-1", number: 1, pageCount: 10),
            ChapterEntity(id: "c-2", number: 2, pageCount: 10),
            ChapterEntity(id: "c-extra", number: nil, pageCount: 4),
        ]
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: chapters),
            mangaRepository: StubMangaRepository(manga: manga)
        )

        await viewModel.markAllAsRead()

        XCTAssertEqual(viewModel.chapters.count, 3)
        XCTAssertEqual(manga.lastReadChapterId, "c-extra")
        XCTAssertEqual(manga.lastReadPageIndex, 3)
        XCTAssertEqual(manga.readingProgress, 1.0, accuracy: 0.0001)
    }

    func testMarkAllAsReadDoesNothingWithoutChapters() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let repository = StubMangaRepository(manga: manga)
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: []),
            mangaRepository: repository
        )

        await viewModel.markAllAsRead()

        XCTAssertNil(manga.lastReadChapterId)
        XCTAssertEqual(repository.saveCount, 0)
    }

    func testRefreshKeepsLocalChaptersWhenTheSiteFails() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let local = ChapterEntity(id: "c-1", number: 1, pageCount: 10)
        let catalog = FailingCatalogService()
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: [local]),
            mangaRepository: StubMangaRepository(manga: manga),
            catalogService: catalog
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.chapters.map(\.id), ["c-1"])
        XCTAssertEqual(viewModel.lastError as? SiteBrowsingError, .searchFailed("offline"))
        XCTAssertFalse(viewModel.isLoadingChapters)
    }

    func testToggleFavoriteRollsBackWhenSavingFails() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let repository = StubMangaRepository(manga: manga)
        repository.saveError = StubFailure.offline
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: []),
            mangaRepository: repository
        )

        await viewModel.toggleFavorite()

        XCTAssertFalse(manga.isFavorite)
        XCTAssertNotNil(viewModel.lastError)
    }

    func testDeleteMangaReportsFailure() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        let repository = StubMangaRepository(manga: manga)
        repository.deleteError = StubFailure.offline
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: []),
            mangaRepository: repository
        )

        let deleted = await viewModel.deleteManga()

        XCTAssertFalse(deleted)
        XCTAssertNotNil(viewModel.lastError)
    }

    func testResumeContinuesAnUnfinishedChapter() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        manga.lastReadChapterId = "c-2"
        manga.lastReadPageIndex = 4
        let chapters = [
            ChapterEntity(id: "c-1", number: 1, pageCount: 10),
            ChapterEntity(id: "c-2", number: 2, pageCount: 10),
            ChapterEntity(id: "c-3", number: 3, pageCount: 10),
        ]
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: chapters),
            mangaRepository: StubMangaRepository(manga: manga)
        )
        await viewModel.loadChapters()

        XCTAssertEqual(viewModel.resumeTarget?.chapter.id, "c-2")
        XCTAssertEqual(viewModel.resumeTarget?.startPosition, .restore)
    }

    func testResumeMovesToTheNextChapterAfterAFinishedOne() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        manga.lastReadChapterId = "c-2"
        manga.lastReadPageIndex = 9
        let chapters = [
            ChapterEntity(id: "c-1", number: 1, pageCount: 10),
            ChapterEntity(id: "c-2", number: 2, pageCount: 10),
            ChapterEntity(id: "c-3", number: 3, pageCount: 10),
        ]
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: chapters),
            mangaRepository: StubMangaRepository(manga: manga)
        )
        await viewModel.loadChapters()

        XCTAssertEqual(viewModel.resumeTarget?.chapter.id, "c-3")
        XCTAssertEqual(viewModel.resumeTarget?.startPosition, .beginning)
    }

    func testResumeOpensTheEndOfTheSeriesWhenItIsFinished() async {
        let manga = MangaEntity(id: "manga", title: "Series")
        manga.lastReadChapterId = "c-3"
        manga.lastReadPageIndex = 9
        let chapters = [
            ChapterEntity(id: "c-1", number: 1, pageCount: 10),
            ChapterEntity(id: "c-2", number: 2, pageCount: 10),
            ChapterEntity(id: "c-3", number: 3, pageCount: 10),
        ]
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: chapters),
            mangaRepository: StubMangaRepository(manga: manga)
        )
        await viewModel.loadChapters()

        XCTAssertEqual(viewModel.resumeTarget?.chapter.id, "c-3")
        XCTAssertEqual(viewModel.resumeTarget?.startPosition, .end)
    }

    func testResumeKeepsAnUnknownLengthChapterInProgress() async {
        // Chapters imported without a page count must not look finished after
        // being opened once, or Resume would skip them.
        let manga = MangaEntity(id: "manga", title: "Series")
        manga.lastReadChapterId = "c-1"
        manga.lastReadPageIndex = 0
        let chapters = [
            ChapterEntity(id: "c-1", number: 1, pageCount: 0),
            ChapterEntity(id: "c-2", number: 2, pageCount: 0),
        ]
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: chapters),
            mangaRepository: StubMangaRepository(manga: manga)
        )
        await viewModel.loadChapters()

        XCTAssertEqual(viewModel.resumeTarget?.chapter.id, "c-1")
        XCTAssertEqual(viewModel.resumeTarget?.startPosition, .restore)
    }

    func testResumeFallsBackToTheLatestProgressEntry() async {
        // Libraries imported before `lastReadChapterId` was persisted only
        // have progress entries.
        let manga = MangaEntity(id: "manga", title: "Series")
        let first = ChapterEntity(id: "c-1", number: 1, pageCount: 10)
        let second = ChapterEntity(id: "c-2", number: 2, pageCount: 10)
        let older = ReadingProgressEntity(pageIndex: 2, totalPages: 10, manga: manga, chapter: first)
        older.readAt = Date(timeIntervalSince1970: 100)
        let newer = ReadingProgressEntity(pageIndex: 4, totalPages: 10, manga: manga, chapter: second)
        newer.readAt = Date(timeIntervalSince1970: 200)
        first.readingProgressEntries = [older]
        second.readingProgressEntries = [newer]

        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: [first, second]),
            mangaRepository: StubMangaRepository(manga: manga)
        )
        await viewModel.loadChapters()

        XCTAssertEqual(viewModel.resumeTarget?.chapter.id, "c-2")
        XCTAssertEqual(viewModel.resumeTarget?.startPosition, .restore)
    }

    func testManualOpenRestartsAFinishedChapterFromTheBeginning() {
        let manga = MangaEntity(id: "manga", title: "Series")
        let chapter = ChapterEntity(id: "c-1", number: 1, pageCount: 10)
        let progress = ReadingProgressEntity(pageIndex: 9, totalPages: 10, manga: manga, chapter: chapter)
        chapter.readingProgressEntries = [progress]

        XCTAssertTrue(chapter.isRead)
        XCTAssertEqual(ReaderEntryPoint.manualStart(for: chapter), .beginning)
    }

    func testManualOpenResumesAnUnfinishedChapter() {
        let manga = MangaEntity(id: "manga", title: "Series")
        let chapter = ChapterEntity(id: "c-1", number: 1, pageCount: 10)
        let progress = ReadingProgressEntity(pageIndex: 3, totalPages: 10, manga: manga, chapter: chapter)
        chapter.readingProgressEntries = [progress]

        XCTAssertFalse(chapter.isRead)
        XCTAssertEqual(ReaderEntryPoint.manualStart(for: chapter), .restore)
    }

    func testManualOpenRestoresAChapterWithoutProgress() {
        let chapter = ChapterEntity(id: "c-1", number: 1, pageCount: 10)

        XCTAssertEqual(ReaderEntryPoint.manualStart(for: chapter), .restore)
    }
}

private enum StubFailure: Error {
    case offline
}

@MainActor
private final class StubChapterRepository: ChapterRepository {
    private var chapters: [ChapterEntity]

    init(chapters: [ChapterEntity]) {
        self.chapters = chapters
    }

    func fetchByMangaId(_ mangaId: String) async throws -> [ChapterEntity] { chapters }
    func fetchById(_ id: String) async throws -> ChapterEntity? { chapters.first { $0.id == id } }
    func fetchByMangaIdAndNumber(_ mangaId: String, number: Double) async throws -> ChapterEntity? {
        chapters.first { $0.number == number }
    }
    func fetchByIds(_ ids: [String]) async throws -> [ChapterEntity] {
        chapters.filter { ids.contains($0.id) }
    }
    func fetchDownloadedChapters(for mangaId: String) async throws -> [ChapterEntity] {
        chapters.filter(\.isDownloaded)
    }
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
    func updateDownloadStatus(_ chapterId: String, isDownloaded: Bool, downloadedPagesCount: Int) async throws {}
}

@MainActor
private final class StubMangaRepository: MangaRepository {
    private(set) var manga: MangaEntity
    private(set) var saveCount = 0
    var saveError: Error?
    var deleteError: Error?

    init(manga: MangaEntity) {
        self.manga = manga
    }

    func fetchAll() async throws -> [MangaEntity] { [manga] }
    func fetchById(_ id: String) async throws -> MangaEntity? { manga.id == id ? manga : nil }
    func fetchByIds(_ ids: [String]) async throws -> [MangaEntity] { ids.contains(manga.id) ? [manga] : [] }
    func fetchFavorites() async throws -> [MangaEntity] { manga.isFavorite ? [manga] : [] }
    func fetchRecent(limit: Int) async throws -> [MangaEntity] { [manga] }
    func fetchByStatus(_ status: MangaStatus) async throws -> [MangaEntity] { manga.status == status ? [manga] : [] }
    func fetchByTag(_ tag: String) async throws -> [MangaEntity] { manga.tags.contains(tag) ? [manga] : [] }
    func search(query: String) async throws -> [MangaEntity] { [] }
    func save(_ manga: MangaEntity) async throws {
        if let saveError { throw saveError }
        self.manga = manga
        saveCount += 1
    }
    func delete(_ manga: MangaEntity) async throws {
        if let deleteError { throw deleteError }
    }
    func deleteAll() async throws {}
    func count() async throws -> Int { 1 }
}

private struct FailingCatalogService: SiteCatalogProviding {
    func search(_ query: SearchQuery, in profiles: [SiteProfile]) async -> SiteSearchOutcome {
        .init(results: [], failures: [])
    }

    func searchNextPage(
        query: SearchQuery,
        in profiles: [SiteProfile],
        continuingFrom outcome: SiteSearchOutcome
    ) async -> SiteSearchOutcome {
        SiteSearchOutcome()
    }

    func importManga(_ result: SiteSearchResult) async throws -> MangaEntity {
        throw SiteBrowsingError.catalogUnavailable
    }

    func refreshChapters(for manga: MangaEntity) async throws {
        throw SiteBrowsingError.searchFailed("offline")
    }
}
