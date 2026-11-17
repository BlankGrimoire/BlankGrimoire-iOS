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

    // MARK: - Text chapters

    func testDetailsDecodeTheTextContentKind() throws {
        let json = """
            {
              "key": "lorem-ipsum",
              "title": "Lorem",
              "status": "ongoing",
              "contentRating": "safe",
              "contentKind": "text"
            }
            """

        let details = try JSONDecoder().decode(MangaDetails.self, from: Data(json.utf8))

        XCTAssertEqual(details.contentKind, .novel)
    }

    @MainActor
    func testDetailsWithoutContentKindKeepTheImageDefault() throws {
        let json = """
            {"key": "lorem-ipsum", "title": "Lorem", "status": "ongoing", "contentRating": "safe"}
            """

        let details = try JSONDecoder().decode(MangaDetails.self, from: Data(json.utf8))

        XCTAssertNil(details.contentKind)
        XCTAssertEqual(details.makeEntity().kind, .comic)
    }

    @MainActor
    func testTextDetailsImportAsNovels() throws {
        let json = """
            {
              "key": "lorem-ipsum",
              "title": "Lorem",
              "status": "ongoing",
              "contentRating": "safe",
              "contentKind": "text"
            }
            """
        let details = try JSONDecoder().decode(MangaDetails.self, from: Data(json.utf8))

        XCTAssertEqual(details.makeEntity().kind, .novel)
    }

    @MainActor
    func testRefreshKeepsTheKindWhenTheAdapterStopsDeclaringIt() throws {
        let manga = MangaEntity(id: "manga", title: "Lorem", kind: .novel)
        let json = """
            {"key": "manga", "title": "Lorem", "status": "ongoing", "contentRating": "safe"}
            """
        let details = try JSONDecoder().decode(MangaDetails.self, from: Data(json.utf8))

        details.apply(to: manga)

        XCTAssertEqual(manga.kind, .novel)
    }

    func testChapterContentDecodesTheContractPayload() throws {
        let json = """
            {
              "key": "lorem-ipsum/chapter-12",
              "title": "Dolor sit amet",
              "body": { "kind": "html", "value": "<p>Lorem ipsum.</p>" },
              "language": "en"
            }
            """

        let content = try JSONDecoder().decode(ChapterContent.self, from: Data(json.utf8))

        XCTAssertEqual(content.key, "lorem-ipsum/chapter-12")
        XCTAssertEqual(content.title, "Dolor sit amet")
        XCTAssertEqual(content.body.kind, .html)
        XCTAssertEqual(content.body.value, "<p>Lorem ipsum.</p>")
    }

    func testTextFormatAcceptsContractAndLegacyValues() throws {
        let contract = try JSONDecoder().decode(TextFormat.self, from: Data("\"text\"".utf8))
        let legacy = try JSONDecoder().decode(TextFormat.self, from: Data("\"plain\"".utf8))

        XCTAssertEqual(contract, .text)
        XCTAssertEqual(legacy, .text)
    }

    func testManifestDecodesContentKindsAndDefaultsToEmpty() throws {
        let withKinds = """
            {
              "id": "theme.example",
              "name": "Example",
              "version": "1.0.0",
              "apiVersion": 1,
              "detectionSignature": { "minScore": 1 },
              "sha256": "\(String(repeating: "a", count: 64))",
              "contentKinds": ["text"]
            }
            """
        let withoutKinds = """
            {
              "id": "theme.example",
              "name": "Example",
              "version": "1.0.0",
              "apiVersion": 1,
              "detectionSignature": { "minScore": 1 },
              "sha256": "\(String(repeating: "a", count: 64))"
            }
            """

        let decoder = JSONDecoder()
        let declared = try decoder.decode(AdapterManifest.self, from: Data(withKinds.utf8))
        let missing = try decoder.decode(AdapterManifest.self, from: Data(withoutKinds.utf8))

        XCTAssertEqual(declared.contentKinds, [.novel])
        XCTAssertTrue(missing.contentKinds.isEmpty)
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
