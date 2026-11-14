// SPDX-License-Identifier: MPL-2.0

import SwiftData
import XCTest

@testable import ReaderCore

@MainActor
final class SiteProfilePersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var persistence: SwiftDataPersistenceManager!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            MangaEntity.self,
            ChapterEntity.self,
            PageEntity.self,
            ReadingProgressEntity.self,
            BookmarkEntity.self,
            SiteProfileEntity.self,
        ])
        let configuration = ModelConfiguration("SiteProfileTests", isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        persistence = try SwiftDataPersistenceManager(container: container)
    }

    override func tearDown() async throws {
        persistence = nil
        container = nil
        try await super.tearDown()
    }

    func testSavesAndFetchesProfile() async throws {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.example",
            themeVersion: "1.0.0",
            selectorOverrides: ThemeSelectorsOverrides(
                search: .init(path: "/search")
            ),
            customHeaders: ["X-Example": "1"]
        )

        try await persistence.siteProfiles.save(profile)

        let fetched = try await persistence.siteProfiles.fetch(id: profile.id)
        XCTAssertEqual(fetched?.name, "Example Site")
        XCTAssertEqual(fetched?.baseURL, "https://example.org")
        XCTAssertEqual(fetched?.themeID, "theme.example")
        XCTAssertEqual(fetched?.selectorOverrides.search?.path, "/search")
        XCTAssertEqual(fetched?.customHeaders["X-Example"], "1")
    }

    func testFetchesByBaseURL() async throws {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.example"
        )
        try await persistence.siteProfiles.save(profile)

        let fetched = try await persistence.siteProfiles.fetchByBaseURL("https://example.org")
        XCTAssertEqual(fetched?.id, profile.id)
    }

    func testUpdatesExistingProfile() async throws {
        var profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.example"
        )
        try await persistence.siteProfiles.save(profile)

        profile.isEnabled = false
        profile.name = "Renamed Site"
        try await persistence.siteProfiles.save(profile)

        let all = try await persistence.siteProfiles.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Renamed Site")
        XCTAssertEqual(all.first?.isEnabled, false)
    }

    func testDeletesProfile() async throws {
        let profile = SiteProfile(
            name: "Example Site",
            baseURL: "https://example.org",
            themeID: "theme.example"
        )
        try await persistence.siteProfiles.save(profile)
        try await persistence.siteProfiles.delete(profile)

        let all = try await persistence.siteProfiles.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }
}
