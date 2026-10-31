// SPDX-License-Identifier: MPL-2.0

import SwiftData
import XCTest

@testable import ReaderCore

@MainActor
final class RepositoryTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var persistenceManager: SwiftDataPersistenceManager!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            MangaEntity.self,
            ChapterEntity.self,
            PageEntity.self,
            ReadingProgressEntity.self,
            BookmarkEntity.self,
        ])

        let configuration = ModelConfiguration(
            "Test",
            isStoredInMemoryOnly: true
        )

        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext

        persistenceManager = try SwiftDataPersistenceManager(container: container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Manga Repository Tests

    func testMangaSaveAndFetch() async throws {
        let manga = MangaEntity(
            id: "manga-1",
            title: "Test Manga",
            status: .ongoing,
            contentRating: .safe
        )

        try await persistenceManager.mangas.save(manga)

        let fetched = try await persistenceManager.mangas.fetchById("manga-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test Manga")
        XCTAssertEqual(fetched?.status, .ongoing)
    }

    func testMangaFetchAll() async throws {
        let manga1 = MangaEntity(id: "1", title: "Manga 1", status: .ongoing, contentRating: .safe)
        let manga2 = MangaEntity(id: "2", title: "Manga 2", status: .completed, contentRating: .safe)
        let manga3 = MangaEntity(id: "3", title: "Manga 3", status: .hiatus, contentRating: .suggestive)

        try await persistenceManager.mangas.save(manga1)
        try await persistenceManager.mangas.save(manga2)
        try await persistenceManager.mangas.save(manga3)

        let all = try await persistenceManager.mangas.fetchAll()
        XCTAssertEqual(all.count, 3)
    }

    func testMangaFetchFavorites() async throws {
        let manga1 = MangaEntity(id: "1", title: "Fav", status: .ongoing, contentRating: .safe)
        manga1.isFavorite = true

        let manga2 = MangaEntity(id: "2", title: "Not Fav", status: .ongoing, contentRating: .safe)

        try await persistenceManager.mangas.save(manga1)
        try await persistenceManager.mangas.save(manga2)

        let favorites = try await persistenceManager.mangas.fetchFavorites()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites[0].id, "1")
    }

    func testMangaFetchByStatus() async throws {
        let manga1 = MangaEntity(id: "1", title: "Ongoing", status: .ongoing, contentRating: .safe)
        let manga2 = MangaEntity(id: "2", title: "Completed", status: .completed, contentRating: .safe)
        let manga3 = MangaEntity(id: "3", title: "Hiatus", status: .hiatus, contentRating: .safe)

        try await persistenceManager.mangas.save(manga1)
        try await persistenceManager.mangas.save(manga2)
        try await persistenceManager.mangas.save(manga3)

        let ongoing = try await persistenceManager.mangas.fetchByStatus(.ongoing)
        XCTAssertEqual(ongoing.count, 1)
        XCTAssertEqual(ongoing[0].id, "1")

        let completed = try await persistenceManager.mangas.fetchByStatus(.completed)
        XCTAssertEqual(completed.count, 1)
    }

    func testMangaSearch() async throws {
        let manga1 = MangaEntity(
            id: "1", title: "Lorem Ipsum", authors: ["Lorem Author"], tags: ["ninja", "action"],
            status: .completed, contentRating: .safe)
        let manga2 = MangaEntity(
            id: "2", title: "Dolor Sit Amet", authors: ["Ipsum Author"], tags: ["pirate", "adventure"],
            status: .ongoing, contentRating: .safe)
        let manga3 = MangaEntity(
            id: "3", title: "Consectetur Elit", authors: ["Dolor Author"], tags: ["dark", "action"],
            status: .completed, contentRating: .mature)

        try await persistenceManager.mangas.save(manga1)
        try await persistenceManager.mangas.save(manga2)
        try await persistenceManager.mangas.save(manga3)

        let results = try await persistenceManager.mangas.search(query: "Lorem")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "1")

        let actionResults = try await persistenceManager.mangas.search(query: "action")
        XCTAssertEqual(actionResults.count, 2)
    }

    func testMangaFetchByTag() async throws {
        let manga1 = MangaEntity(
            id: "1", title: "Manga 1", tags: ["action", "fantasy"], status: .ongoing, contentRating: .safe)
        let manga2 = MangaEntity(
            id: "2", title: "Manga 2", tags: ["romance"], status: .ongoing, contentRating: .safe)
        let manga3 = MangaEntity(
            id: "3", title: "Manga 3", tags: ["action", "romance"], status: .completed, contentRating: .safe)

        try await persistenceManager.mangas.save(manga1)
        try await persistenceManager.mangas.save(manga2)
        try await persistenceManager.mangas.save(manga3)

        let actionManga = try await persistenceManager.mangas.fetchByTag("action")
        XCTAssertEqual(actionManga.count, 2)
    }

    func testMangaDelete() async throws {
        let manga = MangaEntity(id: "1", title: "To Delete", status: .ongoing, contentRating: .safe)
        try await persistenceManager.mangas.save(manga)

        var fetched = try await persistenceManager.mangas.fetchById("1")
        XCTAssertNotNil(fetched)

        try await persistenceManager.mangas.delete(manga)

        fetched = try await persistenceManager.mangas.fetchById("1")
        XCTAssertNil(fetched)
    }

    // MARK: - Chapter Repository Tests

    func testChapterSaveAndFetch() async throws {
        let manga = MangaEntity(id: "manga-1", title: "Test", status: .ongoing, contentRating: .safe)
        let chapter = ChapterEntity(id: "ch-1", title: "ChapterEntity 1", number: 1, pageCount: 20)

        manga.chapters = [chapter]
        chapter.manga = manga

        try await persistenceManager.mangas.save(manga)
        try await persistenceManager.chapters.save(chapter)

        let fetched = try await persistenceManager.chapters.fetchById("ch-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.number, 1)
        XCTAssertEqual(fetched?.manga?.id, "manga-1")
    }

    func testChapterFetchByMangaId() async throws {
        let manga = MangaEntity(id: "manga-1", title: "Test", status: .ongoing, contentRating: .safe)
        let ch1 = ChapterEntity(id: "ch1", number: 1, pageCount: 10)
        let ch2 = ChapterEntity(id: "ch2", number: 2, pageCount: 10)
        let ch3 = ChapterEntity(id: "ch3", number: 3, pageCount: 10)

        manga.chapters = [ch1, ch2, ch3]
        ch1.manga = manga
        ch2.manga = manga
        ch3.manga = manga

        try await persistenceManager.mangas.save(manga)
        try await persistenceManager.chapters.saveAll([ch1, ch2, ch3])

        let chapters = try await persistenceManager.chapters.fetchByMangaId("manga-1")
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters.map(\.number), [1, 2, 3])
    }

    func testChapterDownloadStatus() async throws {
        let chapter = ChapterEntity(id: "ch-1", number: 1, pageCount: 10)

        try await persistenceManager.chapters.save(chapter)

        var fetched = try await persistenceManager.chapters.fetchById("ch-1")
        XCTAssertFalse(fetched!.isDownloaded)

        try await persistenceManager.chapters.updateDownloadStatus("ch-1", isDownloaded: true, downloadedPagesCount: 10)

        fetched = try await persistenceManager.chapters.fetchById("ch-1")
        XCTAssertTrue(fetched!.isDownloaded)
        XCTAssertEqual(fetched?.downloadedPagesCount, 10)
        XCTAssertTrue(fetched!.isFullyDownloaded)
    }

    // MARK: - Page Repository Tests

    func testPageSaveAndFetch() async throws {
        let chapter = ChapterEntity(id: "ch-1", number: 1, pageCount: 3)
        let page1 = PageEntity(index: 0, imageURL: "https://example.org/1.jpg")
        let page2 = PageEntity(index: 1, imageURL: "https://example.org/2.jpg")
        let page3 = PageEntity(index: 2, imageURL: "https://example.org/3.jpg")

        chapter.pages = [page1, page2, page3]
        page1.chapter = chapter
        page2.chapter = chapter
        page3.chapter = chapter

        try await persistenceManager.chapters.save(chapter)
        try await persistenceManager.pages.saveAll([page1, page2, page3])

        let pages = try await persistenceManager.pages.fetchByChapterId(chapter.id)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages.map(\.index), [0, 1, 2])
    }

    func testPageDownloadStatus() async throws {
        let chapter = ChapterEntity(id: "ch-1", pageCount: 2)
        let page = PageEntity(index: 0, imageURL: "https://example.org/1.jpg")

        chapter.pages = [page]
        page.chapter = chapter

        try await persistenceManager.chapters.save(chapter)
        try await persistenceManager.pages.save(page)

        var fetched = try await persistenceManager.pages.fetchById(page.id)
        XCTAssertFalse(fetched!.isDownloaded)

        try await persistenceManager.pages.updateDownloadStatus(
            page.id, isDownloaded: true, localPath: "/local/path/1.jpg")

        fetched = try await persistenceManager.pages.fetchById(page.id)
        XCTAssertTrue(fetched!.isDownloaded)
        XCTAssertEqual(fetched?.localPath, "/local/path/1.jpg")
    }

    // MARK: - Reading Progress Tests

    func testReadingProgressSaveAndFetch() async throws {
        let manga = MangaEntity(id: "manga-1", title: "Test", status: .ongoing, contentRating: .safe)
        let chapter = ChapterEntity(id: "ch-1", number: 1, pageCount: 20)

        let progress = ReadingProgressEntity(
            pageIndex: 5,
            totalPages: 20,
            manga: manga,
            chapter: chapter,
            timeSpent: 120
        )

        try await persistenceManager.readingProgress.save(progress)

        let fetched = try await persistenceManager.readingProgress.fetchByMangaId("manga-1")
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].pageIndex, 5)
        XCTAssertEqual(fetched[0].progress, 0.25)
        XCTAssertEqual(fetched[0].timeSpent, 120)
    }

    func testReadingProgressLatest() async throws {
        let manga = MangaEntity(id: "manga-1", title: "Test", status: .ongoing, contentRating: .safe)
        let chapter = ChapterEntity(id: "ch-1", number: 1, pageCount: 10)

        let progress1 = ReadingProgressEntity(
            pageIndex: 1, totalPages: 10, manga: manga, chapter: chapter, timeSpent: 60)
        let progress2 = ReadingProgressEntity(
            pageIndex: 5, totalPages: 10, manga: manga, chapter: chapter, timeSpent: 300)

        // Manually set readAt to ensure ordering
        progress1.readAt = Date().addingTimeInterval(-3600)
        progress2.readAt = Date()

        try await persistenceManager.readingProgress.save(progress1)
        try await persistenceManager.readingProgress.save(progress2)

        let latest = try await persistenceManager.readingProgress.fetchLatest(for: "manga-1")
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.pageIndex, 5)
    }

    // MARK: - Bookmark Tests

    func testBookmarkSaveAndFetch() async throws {
        let manga = MangaEntity(id: "manga-1", title: "Test", status: .ongoing, contentRating: .safe)
        let chapter = ChapterEntity(id: "ch-1", number: 1, pageCount: 20)

        let bookmark = BookmarkEntity(
            note: "Important scene",
            pageIndex: 10,
            manga: manga,
            chapter: chapter
        )

        try await persistenceManager.bookmarks.save(bookmark)

        let fetched = try await persistenceManager.bookmarks.fetchByMangaId("manga-1")
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].note, "Important scene")
        XCTAssertEqual(fetched[0].pageIndex, 10)
    }

    func testBookmarkFetchByChapter() async throws {
        let manga = MangaEntity(id: "manga-1", title: "Test", status: .ongoing, contentRating: .safe)
        let ch1 = ChapterEntity(id: "ch1", number: 1, pageCount: 10)
        let ch2 = ChapterEntity(id: "ch2", number: 2, pageCount: 10)

        let bm1 = BookmarkEntity(note: "Ch1 bookmark", pageIndex: 5, manga: manga, chapter: ch1)
        let bm2 = BookmarkEntity(note: "Ch2 bookmark", pageIndex: 3, manga: manga, chapter: ch2)

        try await persistenceManager.bookmarks.save(bm1)
        try await persistenceManager.bookmarks.save(bm2)

        let ch1Bookmarks = try await persistenceManager.bookmarks.fetchByChapterId("ch1")
        XCTAssertEqual(ch1Bookmarks.count, 1)
        XCTAssertEqual(ch1Bookmarks[0].note, "Ch1 bookmark")
    }

    // MARK: - Transaction Tests

    func testTransactionRollback() async throws {
        let manga = MangaEntity(id: "tx-1", title: "Transaction Test", status: .ongoing, contentRating: .safe)

        do {
            try await persistenceManager.performInTransaction {
                try await persistenceManager.mangas.save(manga)
                throw NSError(domain: "TestError", code: -1)
            }
            XCTFail("The transaction should have thrown")
        } catch {
            // Expected: the transaction is rolled back.
        }

        let fetched = try await persistenceManager.mangas.fetchById("tx-1")
        XCTAssertNil(fetched)
    }

    // MARK: - Count and Batch Tests

    func testMangaCount() async throws {
        let count1 = try await persistenceManager.mangas.count()

        for i in 1...5 {
            let manga = MangaEntity(id: "\(i)", title: "Manga \(i)", status: .ongoing, contentRating: .safe)
            try await persistenceManager.mangas.save(manga)
        }

        let count2 = try await persistenceManager.mangas.count()
        XCTAssertEqual(count2, count1 + 5)
    }
}
