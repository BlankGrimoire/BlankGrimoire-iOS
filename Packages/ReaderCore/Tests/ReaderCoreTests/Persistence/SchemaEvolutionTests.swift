// SPDX-License-Identifier: MPL-2.0

import SwiftData
import XCTest

@testable import ReaderCore

/// Covers the schema additions for prose content and sync.
@MainActor
final class SchemaEvolutionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var persistenceManager: SwiftDataPersistenceManager!

    override func setUp() async throws {
        try await super.setUp()
        container = try BlankGrimoireSchema.makeContainer(
            isStoredInMemoryOnly: true,
            name: "SchemaEvolutionTests"
        )
        context = container.mainContext
        persistenceManager = try SwiftDataPersistenceManager(container: container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Content kind

    func testSeriesDefaultToComic() {
        let manga = MangaEntity(id: "manga", title: "Series")

        XCTAssertEqual(manga.kind, .comic)
        XCTAssertFalse(manga.kind.isText)
    }

    func testProseKindsReportText() {
        XCTAssertTrue(ContentKind.novel.isText)
        XCTAssertTrue(ContentKind.book.isText)
    }

    func testUnknownContentKindDecodesAsComic() throws {
        // A newer adapter may emit a kind this build does not know; the
        // library must not fail to load because of it.
        let decoded = try JSONDecoder().decode(ContentKind.self, from: Data("\"webtoon\"".utf8))

        XCTAssertEqual(decoded, .comic)
    }

    // MARK: - Chapter text

    func testChapterContentStoresTextAndFormat() throws {
        let manga = MangaEntity(id: "manga", title: "Series", kind: .novel)
        let chapter = ChapterEntity(id: "chapter", number: 1)
        chapter.manga = manga
        let content = ChapterContentEntity(
            body: "<p>Lorem ipsum</p>",
            format: .html,
            wordCount: 2,
            chapter: chapter
        )
        chapter.content = content

        context.insert(manga)
        context.insert(chapter)
        context.insert(content)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ChapterContentEntity>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.format, .html)
        XCTAssertEqual(fetched.first?.chapter?.id, "chapter")
        XCTAssertEqual(fetched.first?.wordCount, 2)
    }

    func testTextPositionIsStoredWithProgress() {
        let manga = MangaEntity(id: "manga", title: "Series", kind: .novel)
        let chapter = ChapterEntity(id: "chapter", number: 1)
        let progress = ReadingProgressEntity(
            pageIndex: 0,
            totalPages: 1,
            manga: manga,
            chapter: chapter,
            textOffset: 4_200
        )

        XCTAssertEqual(progress.textOffset, 4_200)
        XCTAssertNotNil(progress.updatedAt)
    }

    func testBookmarkKeepsATextOffset() {
        let manga = MangaEntity(id: "manga", title: "Series", kind: .novel)
        let bookmark = BookmarkEntity(
            note: "Here",
            pageIndex: 0,
            manga: manga,
            textOffset: 1_024
        )

        XCTAssertEqual(bookmark.textOffset, 1_024)
        XCTAssertNotNil(bookmark.updatedAt)
    }

    // MARK: - Sync tombstones

    func testTombstoneIdentityIsKindScoped() {
        let manga = SyncTombstoneEntity(kind: .manga, recordID: "same-id")
        let chapter = SyncTombstoneEntity(kind: .chapter, recordID: "same-id")

        XCTAssertNotEqual(manga.id, chapter.id)
        XCTAssertEqual(manga.recordKind, .manga)
        XCTAssertEqual(chapter.recordID, "same-id")
    }

    func testDeletingASeriesRecordsTombstonesForItsChildren() async throws {
        let manga = MangaEntity(id: "manga", title: "Series", status: .ongoing, contentRating: .safe)
        let chapter = ChapterEntity(id: "chapter", number: 1, pageCount: 1)
        let progress = ReadingProgressEntity(
            pageIndex: 0,
            totalPages: 1,
            manga: manga,
            chapter: chapter
        )
        let bookmark = BookmarkEntity(note: "Note", pageIndex: 0, manga: manga, chapter: chapter)
        chapter.manga = manga
        chapter.readingProgressEntries = [progress]
        chapter.bookmarks = [bookmark]
        manga.chapters = [chapter]
        manga.readingProgressEntries = [progress]
        manga.bookmarks = [bookmark]

        try await persistenceManager.mangas.save(manga)
        try await persistenceManager.chapters.save(chapter)
        try await persistenceManager.readingProgress.save(progress)
        try await persistenceManager.bookmarks.save(bookmark)

        try await persistenceManager.mangas.delete(manga)

        let tombstones = try context.fetch(FetchDescriptor<SyncTombstoneEntity>())
        let ids = Set(tombstones.map(\.id))

        XCTAssertTrue(ids.contains("manga:manga"))
        XCTAssertTrue(ids.contains("chapter:chapter"))
        XCTAssertTrue(ids.contains("readingProgress:\(progress.id)"))
        XCTAssertTrue(ids.contains("bookmark:\(bookmark.id)"))
    }

    func testTombstoneRecordingIsIdempotent() throws {
        try SyncTombstoneRecorder.record(.manga, ids: ["manga"], in: context)
        try SyncTombstoneRecorder.record(.manga, ids: ["manga"], in: context)

        let tombstones = try context.fetch(FetchDescriptor<SyncTombstoneEntity>())
        XCTAssertEqual(tombstones.count, 1)
    }

    func testDerivedRecordsAreNotSyncData() {
        // Pages and cached chapter text are rebuilt from the site.
        XCTAssertFalse(SyncRecordKind.allCases.map(\.rawValue).contains("page"))
        XCTAssertFalse(SyncRecordKind.allCases.map(\.rawValue).contains("chapterContent"))
    }
}
