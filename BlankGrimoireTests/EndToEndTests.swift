// SPDX-License-Identifier: MPL-2.0

import Foundation
import ReaderCore
import Testing

@testable import BlankGrimoire

/// Gated end-to-end test for the F6 release dry-run.
///
/// It talks to the local HTTPS harness:
///
/// ```bash
/// ./local-test/local-publish.sh --https        # themes repository, port 8443
/// ./local-test/serve-sites.sh                 # site-a :8444, site-b :8445
/// BLANKGRIMMOIRE_E2E=1 make test
/// ```
///
/// The test is skipped unless `BLANKGRIMMOIRE_E2E=1` is present, so the normal
/// suite never depends on a running server. URLs can be overridden with
/// `BLANKGRIMMOIRE_E2E_REPOSITORY_URL`, `BLANKGRIMMOIRE_E2E_SITE_A` and
/// `BLANKGRIMMOIRE_E2E_SITE_B`; the defaults use loopback IPs because ATS does
/// not apply to numeric addresses.
@MainActor
struct EndToEndTests {
    private static let defaults = (
        repository: "https://127.0.0.1:8443/index.json",
        siteA: "https://127.0.0.1:8444",
        siteB: "https://127.0.0.1:8445"
    )

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BLANKGRIMMOIRE_E2E"] == "1"))
    func syntheticSitesEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment

        /// Unset build settings reach the test runner either empty or as the
        /// literal `$(NAME)`; both fall back to the loopback defaults.
        func override(_ key: String) -> String? {
            guard let value = environment[key], value.hasPrefix("https://") else {
                return nil
            }
            return value
        }

        let repositoryURL =
            override("BLANKGRIMMOIRE_E2E_REPOSITORY_URL")
            ?? Self.defaults.repository
        let siteAURL = override("BLANKGRIMMOIRE_E2E_SITE_A") ?? Self.defaults.siteA
        let siteBURL = override("BLANKGRIMMOIRE_E2E_SITE_B") ?? Self.defaults.siteB

        let container = try AppComposition.makeModelContainer(isStoredInMemoryOnly: true)
        let dependencies = try AppComposition.makeDependencies(container: container)
        let adapterStore = try #require(dependencies.adapterStore)
        let catalog = try #require(dependencies.catalogService)
        let detector = try #require(dependencies.themeDetector)
        let pagesProvider = try #require(dependencies.chapterPagesProvider)

        // 1. Repository: fetch, trust and install the theme adapter.
        let index = try await adapterStore.fetchRepositoryIndex(from: repositoryURL)
        #expect(index.formatVersion == 1)
        let entry = try #require(
            index.extensions.first { $0.id == "theme.static-advanced" }
        )
        #expect(entry.version == "1.0.0")

        try await adapterStore.trustRepository(index, from: repositoryURL)
        #expect(try await adapterStore.isRepositoryTrusted(repositoryURL))

        let bundle = try await adapterStore.installAdapter(
            id: entry.id,
            version: entry.version,
            from: repositoryURL
        )
        #expect(bundle.id == entry.id)
        #expect(bundle.themeAdapter.id == entry.id)

        // 2. Two synthetic sites share every path but live on different ports.
        let profileA = SiteProfile(
            name: "Synthetic Site A",
            baseURL: siteAURL,
            themeID: entry.id,
            themeVersion: entry.version
        )
        let profileB = SiteProfile(
            name: "Synthetic Site B",
            baseURL: siteBURL,
            themeID: entry.id,
            themeVersion: entry.version
        )
        try await dependencies.siteProfileRepository.saveIfAbsent(profileA)
        try await dependencies.siteProfileRepository.saveIfAbsent(profileB)

        // 3. Theme detection scores the installed adapter against each home page.
        let detectedA = try await detector.detectTheme(for: siteAURL)
        let detectedB = try await detector.detectTheme(for: siteBURL)
        #expect(detectedA.theme.id == entry.id)
        #expect(detectedB.theme.id == entry.id)
        #expect(detectedA.score >= detectedA.theme.detectionSignature.minScore)
        #expect(detectedB.score >= detectedB.theme.detectionSignature.minScore)

        // 4. Cross-site search returns one result per site.
        let outcome = await catalog.search(query: "lorem", in: [profileA, profileB])
        #expect(outcome.failures.isEmpty)
        #expect(outcome.results.count == 2)

        let resultA = try #require(
            outcome.results.first { $0.siteProfileID == profileA.id }
        )
        let resultB = try #require(
            outcome.results.first { $0.siteProfileID == profileB.id }
        )
        #expect(resultA.key == "\(siteAURL)/series/lorem/")
        #expect(resultB.key == "\(siteBURL)/series/lorem/")
        #expect(resultA.coverURL == "\(siteAURL)/media/cover-a.png")
        #expect(resultB.coverURL == "\(siteBURL)/media/cover-b.png")

        // 5. Import both results: identical adapter keys must not collide.
        let mangaA = try await catalog.importManga(resultA)
        let mangaB = try await catalog.importManga(resultB)
        #expect(mangaA.title == "Lorem Ipsum")
        #expect(mangaB.title == "Lorem Ipsum Mirror")
        #expect(mangaA.id == "\(profileA.id)::\(resultA.key)")
        #expect(mangaB.id == "\(profileB.id)::\(resultB.key)")
        #expect(mangaA.id != mangaB.id)

        let chaptersA = try await dependencies.chapterRepository.fetchByMangaId(mangaA.id)
        let chaptersB = try await dependencies.chapterRepository.fetchByMangaId(mangaB.id)
        #expect(chaptersA.count == 2)
        #expect(chaptersB.count == 2)

        let chapterA = try #require(
            chaptersA.first { $0.adapterKey.hasSuffix("/chapter/1/") }
        )
        let chapterB = try #require(
            chaptersB.first { $0.adapterKey.hasSuffix("/chapter/1/") }
        )
        #expect(chapterA.adapterKey == "\(siteAURL)/chapter/1/")
        #expect(chapterB.adapterKey == "\(siteBURL)/chapter/1/")
        #expect(chapterA.id != chapterB.id)

        // 6. Chapter pages are extracted and scoped to their own site.
        let pagesA = try await pagesProvider.pages(
            for: chapterA,
            manga: mangaA,
            forceRefresh: true
        )
        let pagesB = try await pagesProvider.pages(
            for: chapterB,
            manga: mangaB,
            forceRefresh: true
        )
        #expect(
            pagesA.map { $0.imageURL } == [
                "\(siteAURL)/media/page-1.png",
                "\(siteAURL)/media/page-2.png",
            ])
        #expect(
            pagesB.map { $0.imageURL } == [
                "\(siteBURL)/media/page-1.png",
                "\(siteBURL)/media/page-2.png",
            ])
        #expect(chapterA.pageCount == 2)
        #expect(chapterB.pageCount == 2)
    }
}
