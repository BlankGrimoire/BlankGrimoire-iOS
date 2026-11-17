// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class SiteSearchSelectionTests: XCTestCase {
    func testEveryEnabledSiteStartsSelectedAndDisabledSitesAreSkipped() async {
        let enabled = makeProfile(id: "a", name: "Site A")
        let disabled = makeProfile(id: "b", name: "Site B", isEnabled: false)
        let viewModel = SiteSearchViewModel(
            siteProfileRepository: StubSiteProfileRepository(profiles: [enabled, disabled]),
            catalogService: nil
        )

        await viewModel.loadSites()

        XCTAssertEqual(viewModel.selectedSiteIDs, ["a"])
        XCTAssertEqual(viewModel.targetSites.map(\.id), ["a"])
        XCTAssertTrue(viewModel.areAllSitesSelected)
    }

    func testExcludingASiteNarrowsTheTargets() async {
        let first = makeProfile(id: "a", name: "Site A")
        let second = makeProfile(id: "b", name: "Site B")
        let viewModel = SiteSearchViewModel(
            siteProfileRepository: StubSiteProfileRepository(profiles: [first, second]),
            catalogService: nil
        )
        await viewModel.loadSites()

        viewModel.setSite(first, selected: false)

        XCTAssertEqual(viewModel.targetSites.map(\.id), ["b"])
        XCTAssertFalse(viewModel.areAllSitesSelected)
    }

    func testClearingTheSelectionSurvivesAReload() async {
        // An empty selection must stay empty: re-selecting everything after a
        // reload would silently search sites the user excluded.
        let repository = StubSiteProfileRepository(profiles: [makeProfile(id: "a", name: "Site A")])
        let viewModel = SiteSearchViewModel(
            siteProfileRepository: repository,
            catalogService: nil
        )
        await viewModel.loadSites()
        viewModel.setAllSitesSelected(false)

        await viewModel.loadSites()

        XCTAssertTrue(viewModel.selectedSiteIDs.isEmpty)
        XCTAssertTrue(viewModel.targetSites.isEmpty)
    }

    func testDeletedSitesAreDroppedFromTheSelection() async {
        let first = makeProfile(id: "a", name: "Site A")
        let second = makeProfile(id: "b", name: "Site B")
        let repository = StubSiteProfileRepository(profiles: [first, second])
        let viewModel = SiteSearchViewModel(
            siteProfileRepository: repository,
            catalogService: nil
        )
        await viewModel.loadSites()

        repository.profiles = [first]
        await viewModel.loadSites()

        XCTAssertEqual(viewModel.selectedSiteIDs, ["a"])
    }

    func testSelectAllRestoresEveryEnabledSite() async {
        let first = makeProfile(id: "a", name: "Site A")
        let second = makeProfile(id: "b", name: "Site B")
        let viewModel = SiteSearchViewModel(
            siteProfileRepository: StubSiteProfileRepository(profiles: [first, second]),
            catalogService: nil
        )
        await viewModel.loadSites()
        viewModel.setAllSitesSelected(false)

        viewModel.setAllSitesSelected(true)

        XCTAssertEqual(viewModel.targetSites.map(\.id).sorted(), ["a", "b"])
        XCTAssertTrue(viewModel.areAllSitesSelected)
    }

    private func makeProfile(id: String, name: String, isEnabled: Bool = true) -> SiteProfile {
        SiteProfile(
            id: id,
            name: name,
            baseURL: "https://\(id).example.org",
            themeID: "theme.example",
            isEnabled: isEnabled
        )
    }
}

@MainActor
private final class StubSiteProfileRepository: SiteProfileRepository {
    var profiles: [SiteProfile]

    init(profiles: [SiteProfile]) {
        self.profiles = profiles
    }

    func fetchAll() async throws -> [SiteProfile] { profiles }
    func fetch(id: String) async throws -> SiteProfile? { profiles.first { $0.id == id } }
    func fetchByBaseURL(_ baseURL: String) async throws -> SiteProfile? {
        profiles.first { $0.baseURL == baseURL }
    }
    func save(_ profile: SiteProfile) async throws {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }
    func saveIfAbsent(_ profile: SiteProfile) async throws {
        guard !profiles.contains(where: { $0.id == profile.id || $0.baseURL == profile.baseURL }) else {
            return
        }
        profiles.append(profile)
    }
    func delete(_ profile: SiteProfile) async throws {
        profiles.removeAll { $0.id == profile.id }
    }
}
