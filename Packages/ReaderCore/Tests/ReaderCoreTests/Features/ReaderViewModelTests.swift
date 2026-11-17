// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class ReaderViewModelTests: XCTestCase {
    func testLoadRestoresChapterProgressBeforeMangaFallback() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 3)
        let pages = (0..<3).map { PageEntity(index: $0, imageURL: "https://example.org/page\($0).jpg") }
        let progress = ReadingProgressEntity(
            pageIndex: 1,
            totalPages: 3,
            manga: manga,
            chapter: chapter
        )
        manga.lastReadChapterId = chapter.id
        manga.lastReadPageIndex = 0

        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: pages),
            readingProgressRepository: TestReadingProgressRepository(progress: [progress]),
            mangaRepository: TestMangaRepository(manga: manga)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.currentPageIndex, 1)
        XCTAssertEqual(viewModel.pageNumber, 2)
        XCTAssertEqual(viewModel.progress, 2.0 / 3.0, accuracy: 0.001)
    }

    func testSavingProgressPersistsExactPageAndCompletesLastPage() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 2)
        let progressRepository = TestReadingProgressRepository()
        let mangaRepository = TestMangaRepository(manga: manga)
        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: [
                PageEntity(index: 0, imageURL: "https://example.org/one.jpg"),
                PageEntity(index: 1, imageURL: "https://example.org/two.jpg"),
            ]),
            readingProgressRepository: progressRepository,
            mangaRepository: mangaRepository
        )

        await viewModel.load()
        await viewModel.setPage(index: 1)
        await viewModel.flushProgress()

        XCTAssertEqual(progressRepository.progress.first?.pageIndex, 1)
        XCTAssertEqual(progressRepository.progress.first?.progress ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(manga.lastReadPageIndex, 1)
        XCTAssertEqual(manga.readingProgress, 1.0, accuracy: 0.001)
    }

    func testOpeningChapterWithoutNavigatingDoesNotPersistProgress() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 3)
        let progressRepository = TestReadingProgressRepository()
        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: [
                PageEntity(index: 0, imageURL: "https://example.org/one.jpg"),
                PageEntity(index: 1, imageURL: "https://example.org/two.jpg"),
            ]),
            readingProgressRepository: progressRepository,
            mangaRepository: TestMangaRepository(manga: manga)
        )

        await viewModel.load()
        await viewModel.flushProgress()

        XCTAssertTrue(progressRepository.progress.isEmpty)
        XCTAssertNil(manga.lastReadChapterId)
        XCTAssertEqual(manga.readingProgress, 0, accuracy: 0.0001)
    }

    func testSavingFlagStaysSetWhileAWriteIsInFlight() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 2)
        let progressRepository = TestReadingProgressRepository()
        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: [
                PageEntity(index: 0, imageURL: "https://example.org/one.jpg"),
                PageEntity(index: 1, imageURL: "https://example.org/two.jpg"),
            ]),
            readingProgressRepository: progressRepository,
            mangaRepository: TestMangaRepository(manga: manga)
        )
        await viewModel.load()
        await viewModel.setPage(index: 1)

        var flagsDuringWrite: [Bool] = []
        progressRepository.willSave = { flagsDuringWrite.append(viewModel.isSavingProgress) }

        await viewModel.flushProgress()

        XCTAssertEqual(flagsDuringWrite, [true])
        XCTAssertFalse(viewModel.isSavingProgress)
    }

    func testLoadFallsBackToChapterPagesProviderWhenCacheIsEmpty() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 0)
        let loaded = (0..<2).map { PageEntity(index: $0, imageURL: "https://example.org/loaded\($0).jpg") }

        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: []),
            readingProgressRepository: TestReadingProgressRepository(),
            mangaRepository: TestMangaRepository(manga: manga),
            chapterPagesProvider: TestChapterPagesProvider(pages: loaded)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.pages.map(\.index), [0, 1])
        XCTAssertEqual(viewModel.totalPages, 2)
        XCTAssertNil(viewModel.lastError)
    }

    func testRecordPageSizePersistsDecodedDimensions() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 2)
        let pages = [
            PageEntity(index: 0, imageURL: "https://example.org/one.jpg"),
            PageEntity(index: 1, imageURL: "https://example.org/two.jpg"),
        ]
        let pageRepository = TestPageRepository(pages: pages)
        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: pageRepository,
            readingProgressRepository: TestReadingProgressRepository(),
            mangaRepository: TestMangaRepository(manga: manga)
        )
        await viewModel.load()

        await viewModel.recordPageSize(index: 1, width: 800, height: 1200)

        XCTAssertEqual(pages[1].width, 800)
        XCTAssertEqual(pages[1].height, 1200)
        XCTAssertEqual(pageRepository.savedPages.map(\.index), [1])

        // Reporting the same size again must not write to the store.
        await viewModel.recordPageSize(index: 1, width: 800, height: 1200)
        XCTAssertEqual(pageRepository.savedPages.map(\.index), [1])
    }

    func testRecordPageSizeIgnoresInvalidDimensionsAndIndices() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 1)
        let pages = [PageEntity(index: 0, imageURL: "https://example.org/one.jpg")]
        let pageRepository = TestPageRepository(pages: pages)
        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: pageRepository,
            readingProgressRepository: TestReadingProgressRepository(),
            mangaRepository: TestMangaRepository(manga: manga)
        )
        await viewModel.load()

        await viewModel.recordPageSize(index: 0, width: 0, height: 1200)
        await viewModel.recordPageSize(index: 4, width: 800, height: 1200)

        XCTAssertNil(pages[0].width)
        XCTAssertNil(pages[0].height)
        XCTAssertTrue(pageRepository.savedPages.isEmpty)
    }

    func testTopmostPageIndexUsesTheRowCoveringTheTopEdge() {
        // Page 1 starts above the viewport and page 2 starts below it.
        let offsets: [Int: Double] = [0: -2400, 1: -120, 2: 640, 3: 1600]

        XCTAssertEqual(ReaderViewModel.topmostPageIndex(minYs: offsets), 1)
    }

    func testTopmostPageIndexFallsBackToTheFirstRealisedRow() {
        // Before the first scroll the top edge is above every row.
        let offsets: [Int: Double] = [4: 40, 5: 900, 6: 1780]

        XCTAssertEqual(ReaderViewModel.topmostPageIndex(minYs: offsets), 4)
    }

    func testTopmostPageIndexIsNilWithoutRows() {
        XCTAssertNil(ReaderViewModel.topmostPageIndex(minYs: [:]))
    }

    func testTopmostPageIndexAbsorbsFractionalOffsets() {
        // At the end of the list a row can sit a hair below the top edge.
        let offsets: [Int: Double] = [0: -900, 1: 0.4]

        XCTAssertEqual(ReaderViewModel.topmostPageIndex(minYs: offsets), 1)
    }

    func testCurrentPageBecomesTheLastPageWhenItIsFullyVisible() {
        // A short last image never reaches the top edge, so covering the top
        // would leave the chapter unfinished forever.
        let offsets: [Int: Double] = [0: -1800, 1: -400, 2: 320]

        let index = ReaderViewModel.currentPageIndex(
            minYs: offsets,
            lastPageIndex: 2,
            lastPageBottom: 600,
            viewportHeight: 800
        )

        XCTAssertEqual(index, 2)
    }

    func testCurrentPageStaysOnTheTopRowWhileTheLastPageIsBelowTheFold() {
        let offsets: [Int: Double] = [0: -1800, 1: -400, 2: 320]

        let index = ReaderViewModel.currentPageIndex(
            minYs: offsets,
            lastPageIndex: 2,
            lastPageBottom: 1200,
            viewportHeight: 800
        )

        XCTAssertEqual(index, 1)
    }

    func testCurrentPageIgnoresAnUnrealisedLastPage() {
        // The lazy stack has not built the last row yet.
        let offsets: [Int: Double] = [0: -100, 1: 700]

        let index = ReaderViewModel.currentPageIndex(
            minYs: offsets,
            lastPageIndex: 9,
            lastPageBottom: nil,
            viewportHeight: 800
        )

        XCTAssertEqual(index, 0)
    }

    func testCurrentPageIsNilWithoutRows() {
        XCTAssertNil(
            ReaderViewModel.currentPageIndex(
                minYs: [:],
                lastPageIndex: 0,
                lastPageBottom: nil,
                viewportHeight: 800
            )
        )
    }

    func testStartPositionBeginningIgnoresSavedProgress() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 3)
        let progress = ReadingProgressEntity(
            pageIndex: 2,
            totalPages: 3,
            manga: manga,
            chapter: chapter
        )
        let pages = (0..<3).map { PageEntity(index: $0, imageURL: "https://example.org/page\($0).jpg") }

        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: pages),
            readingProgressRepository: TestReadingProgressRepository(progress: [progress]),
            mangaRepository: TestMangaRepository(manga: manga),
            startPosition: .beginning
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.currentPageIndex, 0)
        XCTAssertEqual(viewModel.pageNumber, 1)
    }

    func testStartPositionEndOpensLastPage() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 3)
        let pages = (0..<3).map { PageEntity(index: $0, imageURL: "https://example.org/page\($0).jpg") }

        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: pages),
            readingProgressRepository: TestReadingProgressRepository(),
            mangaRepository: TestMangaRepository(manga: manga),
            startPosition: .end
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.currentPageIndex, 2)
        XCTAssertEqual(viewModel.pageNumber, 3)
        XCTAssertEqual(viewModel.progress, 1.0, accuracy: 0.001)
    }

    func testReloadKeepsTheCurrentPageInsteadOfTheEntryPoint() async {
        let manga = MangaEntity(id: "manga", title: "Lorem")
        let chapter = ChapterEntity(id: "chapter", pageCount: 3)
        let pages = (0..<3).map { PageEntity(index: $0, imageURL: "https://example.org/page\($0).jpg") }
        let loaded = pages.map { PageEntity(index: $0.index, imageURL: $0.imageURL) }

        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            pageRepository: TestPageRepository(pages: pages),
            readingProgressRepository: TestReadingProgressRepository(),
            mangaRepository: TestMangaRepository(manga: manga),
            chapterPagesProvider: TestChapterPagesProvider(pages: loaded),
            startPosition: .beginning
        )
        await viewModel.load()
        await viewModel.setPage(index: 2)

        await viewModel.reload()

        // A reload after a challenge must not send the reader back to page 1.
        XCTAssertEqual(viewModel.currentPageIndex, 2)
    }
}

@MainActor
private final class TestChapterPagesProvider: ChapterPagesProviding {
    let pages: [PageEntity]

    init(pages: [PageEntity]) {
        self.pages = pages
    }

    func pages(
        for chapter: ChapterEntity,
        manga: MangaEntity,
        forceRefresh: Bool
    ) async throws -> [PageEntity] {
        pages
    }
}

@MainActor
private final class TestPageRepository: PageRepository {
    var pages: [PageEntity]
    var savedPages: [PageEntity] = []

    init(pages: [PageEntity]) {
        self.pages = pages
    }

    func fetchByChapterId(_ chapterId: String) async throws -> [PageEntity] { pages }
    func fetchById(_ id: String) async throws -> PageEntity? { pages.first { $0.id == id } }
    func fetchByChapterIdAndIndex(_ chapterId: String, index: Int) async throws -> PageEntity? {
        pages.first { $0.index == index }
    }
    func save(_ page: PageEntity) async throws {
        savedPages.append(page)
    }
    func saveAll(_ pages: [PageEntity]) async throws {}
    func delete(_ page: PageEntity) async throws {}
    func deleteAll(for chapterId: String) async throws {}
    func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws {}
}

@MainActor
private final class TestReadingProgressRepository: ReadingProgressRepository {
    var progress: [ReadingProgressEntity]
    var willSave: (@MainActor () -> Void)?

    init(progress: [ReadingProgressEntity] = []) {
        self.progress = progress
    }

    func fetchByMangaId(_ mangaId: String) async throws -> [ReadingProgressEntity] {
        progress.filter { $0.manga?.id == mangaId }
    }

    func fetchByMangaIdAndChapterId(_ mangaId: String, chapterId: String) async throws -> [ReadingProgressEntity] {
        progress.filter { $0.manga?.id == mangaId && $0.chapter?.id == chapterId }
    }

    func fetchLatest(for mangaId: String) async throws -> ReadingProgressEntity? {
        progress.filter { $0.manga?.id == mangaId }.max { $0.readAt < $1.readAt }
    }

    func save(_ progress: ReadingProgressEntity) async throws {
        willSave?()
        if let index = self.progress.firstIndex(where: { $0.id == progress.id }) {
            self.progress[index] = progress
        } else {
            self.progress.append(progress)
        }
    }

    func delete(_ progress: ReadingProgressEntity) async throws {
        self.progress.removeAll { $0.id == progress.id }
    }

    func deleteAll(for mangaId: String) async throws {
        progress.removeAll { $0.manga?.id == mangaId }
    }
}

@MainActor
private final class TestMangaRepository: MangaRepository {
    var manga: MangaEntity

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
    func save(_ manga: MangaEntity) async throws { self.manga = manga }
    func delete(_ manga: MangaEntity) async throws {}
    func deleteAll() async throws {}
    func count() async throws -> Int { 1 }
}
