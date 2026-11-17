// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class NewChapterBadgeTests: XCTestCase {
    func testFreshSeriesReportsNoNewChapters() {
        let manga = makeManga(chapters: [1, 2, 3])
        manga.markChaptersSeen()

        XCTAssertEqual(manga.newChapterCount, 0)
    }

    func testChaptersAddedAfterTheMarkerAreNew() {
        let manga = makeManga(chapters: [1, 2, 3])
        manga.markChaptersSeen()

        manga.chapters.append(makeChapter(manga: manga, number: 4))
        manga.chapters.append(makeChapter(manga: manga, number: 5))

        XCTAssertEqual(manga.newChapterCount, 2)
    }

    func testMarkerIsNewestChapterInReadingOrder() {
        // Chapters can arrive out of order; the marker must be the last one in
        // numeric order, not the last one appended.
        let manga = makeManga(chapters: [2, 1])
        manga.markChaptersSeen()

        XCTAssertEqual(manga.lastSeenChapterId, "c-2")
    }

    func testUnknownMarkerReportsNothing() {
        // The marker can disappear when the site removes a chapter; guessing
        // would badge every chapter at once.
        let manga = makeManga(chapters: [1, 2])
        manga.lastSeenChapterId = "removed"

        XCTAssertEqual(manga.newChapterCount, 0)
    }

    func testNoMarkerReportsNothing() {
        // An existing library upgraded to this build has no marker yet.
        let manga = makeManga(chapters: [1, 2, 3])

        XCTAssertNil(manga.lastSeenChapterId)
        XCTAssertEqual(manga.newChapterCount, 0)
    }

    func testOpeningTheDetailClearsTheBadge() async {
        let manga = makeManga(chapters: [1, 2])
        manga.markChaptersSeen()
        manga.chapters.append(makeChapter(manga: manga, number: 3))
        XCTAssertEqual(manga.newChapterCount, 1)

        let repository = StubMangaRepository(manga: manga)
        let viewModel = MangaDetailViewModel(
            manga: manga,
            chapterRepository: StubChapterRepository(chapters: manga.chaptersInReadingOrder),
            mangaRepository: repository
        )

        await viewModel.loadChapters()

        XCTAssertEqual(manga.newChapterCount, 0)
        XCTAssertEqual(manga.lastSeenChapterId, "c-3")
        XCTAssertEqual(repository.saveCount, 1)
    }

    private func makeManga(chapters numbers: [Int]) -> MangaEntity {
        let manga = MangaEntity(id: "manga", title: "Series")
        manga.chapters = numbers.map { makeChapter(manga: manga, number: $0) }
        return manga
    }

    private func makeChapter(manga: MangaEntity, number: Int) -> ChapterEntity {
        let chapter = ChapterEntity(id: "c-\(number)", number: Double(number), pageCount: 1)
        chapter.manga = manga
        return chapter
    }
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
    func save(_ chapter: ChapterEntity) async throws {}
    func saveAll(_ chapters: [ChapterEntity]) async throws {}
    func delete(_ chapter: ChapterEntity) async throws {}
    func deleteAll(for mangaId: String) async throws {}
    func updateDownloadStatus(_ chapterId: String, isDownloaded: Bool, downloadedPagesCount: Int) async throws {}
}

@MainActor
private final class StubMangaRepository: MangaRepository {
    private(set) var manga: MangaEntity
    private(set) var saveCount = 0

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
        self.manga = manga
        saveCount += 1
    }
    func delete(_ manga: MangaEntity) async throws {}
    func deleteAll() async throws {}
    func count() async throws -> Int { 1 }
}
