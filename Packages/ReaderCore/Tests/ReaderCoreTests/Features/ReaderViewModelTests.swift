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

        XCTAssertEqual(progressRepository.progress.first?.pageIndex, 1)
        XCTAssertEqual(progressRepository.progress.first?.progress ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(manga.lastReadPageIndex, 1)
        XCTAssertEqual(manga.readingProgress, 1.0, accuracy: 0.001)
    }
}

@MainActor
private final class TestPageRepository: PageRepository {
    var pages: [PageEntity]

    init(pages: [PageEntity]) {
        self.pages = pages
    }

    func fetchByChapterId(_ chapterId: String) async throws -> [PageEntity] { pages }
    func fetchById(_ id: String) async throws -> PageEntity? { pages.first { $0.id == id } }
    func fetchByChapterIdAndIndex(_ chapterId: String, index: Int) async throws -> PageEntity? {
        pages.first { $0.index == index }
    }
    func save(_ page: PageEntity) async throws {}
    func saveAll(_ pages: [PageEntity]) async throws {}
    func delete(_ page: PageEntity) async throws {}
    func deleteAll(for chapterId: String) async throws {}
    func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws {}
}

@MainActor
private final class TestReadingProgressRepository: ReadingProgressRepository {
    var progress: [ReadingProgressEntity]

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
