// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import SwiftData
import XCTest

final class ThemeSourceTests: XCTestCase {

    private var localSource: LocalThemeSource!
    private var adapterStore: DefaultAdapterStore!
    private var requestHandler: PluginRequestHandler!

    override func setUp() async throws {
        try await super.setUp()

        requestHandler = PluginRequestHandler(
            policy: SiteNetworkPolicy(
                baseURL: "https://example.org",
                allowedHosts: ["example.org"]
            )
        )

        adapterStore = try await DefaultAdapterStore.createInMemory(requestHandler: requestHandler)

        localSource = LocalThemeSource(adapterStore: adapterStore)
    }

    func testLocalThemeSourceListThemes() async throws {
        let theme1 = ThemeAdapter(
            id: "theme.one",
            name: "Theme One",
            version: "1.0.0",
            detectionSignature: ThemeSignature(minScore: 1),
            selectors: makeTestSelectors()
        )
        let theme2 = ThemeAdapter(
            id: "theme.two",
            name: "Theme Two",
            version: "1.0.0",
            detectionSignature: ThemeSignature(minScore: 1),
            selectors: makeTestSelectors()
        )

        try await installTheme(theme1)
        try await installTheme(theme2)

        let themes = try await localSource.listThemes()

        XCTAssertEqual(themes.count, 2)
        XCTAssertTrue(themes.contains { $0.id == "theme.one" })
        XCTAssertTrue(themes.contains { $0.id == "theme.two" })
    }

    func testLocalThemeSourceGetTheme() async throws {
        let theme = ThemeAdapter(
            id: "theme.get",
            name: "Get Theme",
            version: "2.0.0",
            detectionSignature: ThemeSignature(minScore: 1),
            selectors: makeTestSelectors()
        )

        try await installTheme(theme)

        let fetched = try await localSource.getTheme(id: "theme.get")

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, "theme.get")
        XCTAssertEqual(fetched?.version, "2.0.0")
    }

    func testLocalThemeSourceGetNonExistentTheme() async throws {
        let fetched = try await localSource.getTheme(id: "theme.nonexistent")

        XCTAssertNil(fetched)
    }

    func testLocalThemeSourceHasTheme() async throws {
        let theme = ThemeAdapter(
            id: "theme.exists",
            name: "Exists Theme",
            version: "1.0.0",
            detectionSignature: ThemeSignature(minScore: 1),
            selectors: makeTestSelectors()
        )

        try await installTheme(theme)

        let has = try await localSource.hasTheme(id: "theme.exists")
        let notHas = try await localSource.hasTheme(id: "theme.missing")

        XCTAssertTrue(has)
        XCTAssertFalse(notHas)
    }

    func testCompositeThemeSource() async throws {
        // Test composite with same source (deduplication)
        let source1 = LocalThemeSource(adapterStore: adapterStore)
        let source2 = LocalThemeSource(adapterStore: adapterStore)

        let theme1 = ThemeAdapter(
            id: "theme.a", name: "A", version: "1.0.0", detectionSignature: ThemeSignature(minScore: 1),
            selectors: makeTestSelectors())
        let theme2 = ThemeAdapter(
            id: "theme.b", name: "B", version: "1.0.0", detectionSignature: ThemeSignature(minScore: 1),
            selectors: makeTestSelectors())

        try await installTheme(theme1)
        try await installTheme(theme2)

        let composite = CompositeThemeSource(sources: [source1, source2])

        let themes = try await composite.listThemes()

        XCTAssertEqual(themes.count, 2)
        XCTAssertTrue(themes.contains { $0.id == "theme.a" })
        XCTAssertTrue(themes.contains { $0.id == "theme.b" })

        let fetched = try await composite.getTheme(id: "theme.b")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, "theme.b")
    }

    func testCompositeThemeSourceDeduplication() async throws {
        let theme = ThemeAdapter(
            id: "theme.dup", name: "Dup", version: "1.0.0", detectionSignature: ThemeSignature(minScore: 1),
            selectors: makeTestSelectors())

        try await installTheme(theme)

        // Create a second source with the same theme (simulating two sources with same theme)
        let source1 = LocalThemeSource(adapterStore: adapterStore)
        let source2 = LocalThemeSource(adapterStore: adapterStore)

        let composite = CompositeThemeSource(sources: [source1, source2])

        let themes = try await composite.listThemes()

        // Should only appear once despite being in both sources
        XCTAssertEqual(themes.count, 1)
        XCTAssertEqual(themes.first?.id, "theme.dup")
    }

    // MARK: - Helpers

    private func installTheme(_ theme: ThemeAdapter) async throws {
        let manifest = AdapterManifest(
            id: theme.id,
            name: theme.name,
            version: theme.version,
            apiVersion: 1,
            detectionSignature: theme.detectionSignature,
            sha256: String(repeating: "0", count: 64)
        )
        let bundle = AdapterBundle(
            manifest: manifest,
            themeAdapter: theme,
            bundleData: Data("test".utf8),
            sourceRepositoryURL: "https://example.org"
        )
        let entity = InstalledAdapterEntity(bundle: bundle)
        try await adapterStore.insertInstalledAdapterForTesting(entity)
    }

    private func makeTestSelectors() -> ThemeSelectors {
        ThemeSelectors(
            search: .init(
                path: "/search", item: ".result", title: ".title", link: "a", cover: "img", nextPage: ".next"),
            details: .init(
                title: "h1", cover: ".cover img", synopsis: ".synopsis", authors: ".authors", artists: ".artists",
                altTitles: ".alt-titles", tags: ".tags", status: ".status", contentRating: ".rating"),
            chapters: .init(item: ".chapter", link: "a", title: ".title", date: ".date", order: "desc"),
            pages: .init(strategies: [ExtractionStrategy.css(.init(image: ".reader img", srcAttributes: ["src"]))]),
            attribution: .init(logo: ".logo img", credits: ".credits")
        )
    }
}
