// SPDX-License-Identifier: MPL-2.0

import SwiftData
import XCTest

@testable import ReaderCore

@MainActor
final class DomainEntityTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

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
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Manga Tests

    func testMangaCreation() throws {
        let manga = MangaEntity(
            id: "test-1",
            title: "Test Manga",
            coverURL: "https://example.org/cover.jpg",
            altTitles: ["Alt Title"],
            authors: ["Author One"],
            artists: ["Artist One"],
            synopsis: "Test synopsis",
            tags: ["action", "fantasy"],
            status: .ongoing,
            contentRating: .safe
        )

        context.insert(manga)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MangaEntity>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].title, "Test Manga")
        XCTAssertEqual(fetched[0].authors, ["Author One"])
        XCTAssertEqual(fetched[0].status, .ongoing)
        XCTAssertEqual(fetched[0].contentRating, .safe)
    }

    func testMangaRelationships() throws {
        let manga = MangaEntity(
            id: "manga-1",
            title: "Test Manga",
            status: .ongoing,
            contentRating: .safe
        )

        let chapter = ChapterEntity(
            id: "chapter-1",
            title: "ChapterEntity 1",
            number: 1,
            pageCount: 10
        )

        let page = PageEntity(
            index: 0,
            imageURL: "https://example.org/page1.jpg"
        )

        // Set up relationships
        manga.chapters = [chapter]
        chapter.manga = manga
        chapter.pages = [page]
        page.chapter = chapter

        context.insert(manga)
        context.insert(chapter)
        context.insert(page)
        try context.save()

        // Verify relationships
        let fetchedManga = try context.fetch(FetchDescriptor<MangaEntity>()).first!
        XCTAssertEqual(fetchedManga.chapters.count, 1)
        XCTAssertEqual(fetchedManga.chapters[0].pages.count, 1)
    }

    func testMangaUpdateLastRead() throws {
        let manga = MangaEntity(
            id: "manga-1",
            title: "Test Manga",
            status: .ongoing,
            contentRating: .safe
        )

        let chapter = ChapterEntity(
            id: "chapter-1",
            title: "ChapterEntity 1",
            number: 1,
            pageCount: 20
        )

        context.insert(manga)
        context.insert(chapter)
        try context.save()

        manga.updateLastRead(chapterId: "chapter-1", pageIndex: 5, totalPages: 20)
        try context.save()

        XCTAssertEqual(manga.lastReadChapterId, "chapter-1")
        XCTAssertEqual(manga.lastReadPageIndex, 5)
        XCTAssertEqual(manga.readingProgress, 5.0 / 20.0, accuracy: 0.001)
    }

    // MARK: - Chapter Tests

    func testChapterCreation() throws {
        let chapter = ChapterEntity(
            id: "chapter-1",
            title: "ChapterEntity 1",
            number: 1.5,
            volume: 1,
            language: "en",
            pageCount: 20
        )

        XCTAssertEqual(chapter.number, 1.5)
        XCTAssertEqual(chapter.volume, 1)
        XCTAssertEqual(chapter.language, "en")
        XCTAssertEqual(chapter.pageCount, 20)
        XCTAssertFalse(chapter.isDownloaded)
    }

    func testChapterDownloadStatus() throws {
        let chapter = ChapterEntity(
            id: "chapter-1",
            pageCount: 10
        )

        XCTAssertFalse(chapter.isFullyDownloaded)

        chapter.isDownloaded = true
        chapter.downloadedPagesCount = 10

        XCTAssertTrue(chapter.isFullyDownloaded)

        chapter.downloadedPagesCount = 5
        XCTAssertFalse(chapter.isFullyDownloaded)
    }

    // MARK: - Page Tests

    func testPageCreation() throws {
        let page = PageEntity(
            index: 0,
            imageURL: "https://example.org/page1.jpg",
            headers: ["Referer": "https://example.org"]
        )

        XCTAssertEqual(page.index, 0)
        XCTAssertEqual(page.imageURL, "https://example.org/page1.jpg")
        XCTAssertEqual(page.headers?["Referer"], "https://example.org")
        XCTAssertFalse(page.isDownloaded)
    }

    // MARK: - ReadingProgress Tests

    func testReadingProgressCreation() throws {
        let manga = MangaEntity(
            id: "manga-1",
            title: "Test",
            status: .ongoing,
            contentRating: .safe
        )

        let chapter = ChapterEntity(
            id: "chapter-1",
            number: 1,
            pageCount: 20
        )

        let progress = ReadingProgressEntity(
            pageIndex: 5,
            totalPages: 20,
            manga: manga,
            chapter: chapter,
            timeSpent: 300
        )

        XCTAssertEqual(progress.pageIndex, 5)
        XCTAssertEqual(progress.totalPages, 20)
        XCTAssertEqual(progress.progress, 0.25)
        XCTAssertEqual(progress.timeSpent, 300)
        XCTAssertEqual(progress.progressPercentage, 25)
    }

    // MARK: - Bookmark Tests

    func testBookmarkCreation() throws {
        let manga = MangaEntity(
            id: "manga-1",
            title: "Test",
            status: .ongoing,
            contentRating: .safe
        )

        let chapter = ChapterEntity(
            id: "chapter-1",
            number: 1,
            pageCount: 20
        )

        let bookmark = BookmarkEntity(
            note: "Important scene",
            pageIndex: 10,
            manga: manga,
            chapter: chapter
        )

        XCTAssertEqual(bookmark.note, "Important scene")
        XCTAssertEqual(bookmark.pageIndex, 10)
        XCTAssertEqual(bookmark.manga?.id, "manga-1")
        XCTAssertEqual(bookmark.chapter?.id, "chapter-1")
    }

    // MARK: - Enum Tests

    func testMangaStatusDisplay() {
        XCTAssertEqual(MangaStatus.ongoing.displayName, "In corso")
        XCTAssertEqual(MangaStatus.completed.displayName, "Completato")
        XCTAssertEqual(MangaStatus.hiatus.displayName, "In pausa")
        XCTAssertEqual(MangaStatus.cancelled.displayName, "Interrotto")
        XCTAssertEqual(MangaStatus.unknown.displayName, "Sconosciuto")
    }

    func testContentRatingDisplay() {
        XCTAssertEqual(ContentRating.safe.displayName, "Tutti")
        XCTAssertEqual(ContentRating.suggestive.displayName, "Adolescenti")
        XCTAssertEqual(ContentRating.mature.displayName, "Adulti")
        XCTAssertEqual(ContentRating.unknown.displayName, "Sconosciuto")
    }

    // MARK: - Manga Extension Tests

    func testMangaDisplayExtensions() throws {
        let manga = MangaEntity(
            id: "manga-1",
            title: "Test Manga",
            authors: ["Author One", "Author Two"],
            artists: ["Artist One"],
            tags: ["action", "fantasy", "isekai"],
            status: .ongoing,
            contentRating: .safe
        )

        XCTAssertEqual(manga.displayTitle, "Test Manga")
        XCTAssertEqual(manga.authorsDisplay, "Author One, Author Two")
        XCTAssertEqual(manga.artistsDisplay, "Artist One")
        XCTAssertEqual(manga.tagsDisplay, "action, fantasy, isekai")
    }

    func testMangaLatestChapter() throws {
        let manga = MangaEntity(
            id: "manga-1",
            title: "Test",
            status: .ongoing,
            contentRating: .safe
        )

        let chapter1 = ChapterEntity(id: "ch1", number: 1, pageCount: 10)
        let chapter2 = ChapterEntity(id: "ch2", number: 2, pageCount: 10)
        let chapterOnePointFive = ChapterEntity(id: "ch1.5", number: 1.5, pageCount: 10)

        manga.chapters = [chapter1, chapter2, chapterOnePointFive]

        let latest = manga.latestChapter
        XCTAssertEqual(latest?.number, 2)
    }
}
