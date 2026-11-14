// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import XCTest

final class DTOMappingTests: XCTestCase {

    private var fixturesURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        guard let resourcesURL = Bundle.module.resourceURL else {
            throw XCTSkip("Could not locate test bundle resources")
        }

        let candidates = [
            resourcesURL.appendingPathComponent("v1"),
            resourcesURL
                .appendingPathComponent("Contract")
                .appendingPathComponent("fixtures")
                .appendingPathComponent("v1"),
        ]

        guard
            let fixturesURL = candidates.first(where: {
                FileManager.default.fileExists(atPath: $0.path)
            })
        else {
            throw XCTSkip("Could not locate contract fixtures in test bundle")
        }

        self.fixturesURL = fixturesURL
    }

    // MARK: - Manga

    @MainActor
    func testSummaryMapsToPartialEntity() throws {
        let summary = try fixture(MangaSummary.self, "manga-summary.json")

        let entity = summary.makeEntity()

        XCTAssertEqual(entity.id, "lorem-ipsum")
        XCTAssertEqual(entity.title, "Lorem Ipsum")
        XCTAssertEqual(entity.coverURL, "https://example.org/covers/lorem-ipsum.jpg")
        XCTAssertTrue(entity.altTitles.isEmpty)
        XCTAssertTrue(entity.authors.isEmpty)
        XCTAssertTrue(entity.artists.isEmpty)
        XCTAssertNil(entity.synopsis)
        XCTAssertTrue(entity.tags.isEmpty)
        XCTAssertEqual(entity.status, .unknown)
        XCTAssertEqual(entity.contentRating, .unknown)
        XCTAssertFalse(entity.isFavorite)
    }

    @MainActor
    func testDetailsMapsToCompleteEntity() throws {
        let details = try fixture(MangaDetails.self, "manga-details.json")

        let entity = details.makeEntity(isFavorite: true)

        XCTAssertEqual(entity.id, "lorem-ipsum")
        XCTAssertEqual(entity.title, "Lorem Ipsum")
        XCTAssertEqual(entity.coverURL, "https://example.org/covers/lorem-ipsum.jpg")
        XCTAssertEqual(entity.altTitles, ["Dolor Sit Amet"])
        XCTAssertEqual(entity.authors, ["Lorem Author"])
        XCTAssertEqual(entity.artists, ["Ipsum Artist"])
        XCTAssertEqual(entity.synopsis, "Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
        XCTAssertEqual(entity.tags, ["lorem", "ipsum"])
        XCTAssertEqual(entity.status, .ongoing)
        XCTAssertEqual(entity.contentRating, .safe)
        XCTAssertTrue(entity.isFavorite)
    }

    @MainActor
    func testUnknownDetailsMapToUnknownEnums() throws {
        let details = try fixture(MangaDetails.self, "manga-details-unknown-status.json")

        let entity = details.makeEntity()

        XCTAssertEqual(entity.status, .unknown)
        XCTAssertEqual(entity.contentRating, .unknown)
        XCTAssertTrue(entity.altTitles.isEmpty)
        XCTAssertTrue(entity.tags.isEmpty)
    }

    @MainActor
    func testApplyRefreshesRemoteFieldsAndPreservesLocalState() throws {
        let details = try fixture(MangaDetails.self, "manga-details.json")
        let entity = MangaEntity(
            id: "lorem-ipsum",
            title: "Old title",
            status: .hiatus,
            contentRating: .mature,
            isFavorite: true
        )
        entity.lastReadChapterId = "local-chapter"
        let previousUpdatedAt = entity.updatedAt

        details.apply(to: entity)

        XCTAssertEqual(entity.title, "Lorem Ipsum")
        XCTAssertEqual(entity.coverURL, "https://example.org/covers/lorem-ipsum.jpg")
        XCTAssertEqual(entity.altTitles, ["Dolor Sit Amet"])
        XCTAssertEqual(entity.authors, ["Lorem Author"])
        XCTAssertEqual(entity.artists, ["Ipsum Artist"])
        XCTAssertEqual(entity.synopsis, "Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
        XCTAssertEqual(entity.tags, ["lorem", "ipsum"])
        XCTAssertEqual(entity.status, .ongoing)
        XCTAssertEqual(entity.contentRating, .safe)
        XCTAssertTrue(entity.isFavorite)
        XCTAssertEqual(entity.lastReadChapterId, "local-chapter")
        XCTAssertGreaterThanOrEqual(entity.updatedAt, previousUpdatedAt)
    }

    // MARK: - Chapter and page

    @MainActor
    func testChapterMapsToEntityAndParsesDate() throws {
        let chapter = try fixture(Chapter.self, "chapter.json")
        let manga = MangaEntity(id: "lorem-ipsum", title: "Lorem Ipsum")

        let entity = chapter.makeEntity(manga: manga, pageCount: 12)

        XCTAssertEqual(entity.id, "lorem-ipsum/chapter-12-5")
        XCTAssertEqual(entity.title, "Dolor sit amet")
        XCTAssertEqual(entity.number, 12.5)
        XCTAssertEqual(entity.volume, 2)
        XCTAssertEqual(entity.language, "en")
        XCTAssertEqual(entity.group, "Lorem Group")
        XCTAssertEqual(entity.pageCount, 12)
        XCTAssertEqual(entity.manga?.id, "lorem-ipsum")

        let expectedDate = ISO8601DateFormatter().date(from: "2026-01-15T10:00:00Z")
        XCTAssertEqual(entity.publishedAt, expectedDate)
    }

    @MainActor
    func testPageMapsToEntityAndPreservesHeaders() throws {
        let page = try fixture(Page.self, "page.json")
        let chapter = ChapterEntity(id: "lorem-ipsum/chapter-12-5")

        let entity = page.makeEntity(chapter: chapter)

        XCTAssertEqual(entity.index, 0)
        XCTAssertEqual(entity.imageURL, "https://example.org/images/lorem-ipsum/12-5/001.jpg")
        XCTAssertEqual(entity.headers, ["Referer": "https://example.org/"])
        XCTAssertEqual(entity.chapter?.id, "lorem-ipsum/chapter-12-5")
    }

    // MARK: - Helpers

    private func fixture<T: Decodable>(_ type: T.Type, _ filename: String) throws -> T {
        let url = fixturesURL.appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}
