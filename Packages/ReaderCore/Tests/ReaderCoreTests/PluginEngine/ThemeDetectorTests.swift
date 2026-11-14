// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import SwiftData
import XCTest

@MainActor
final class ThemeDetectorTests: XCTestCase {

    private var detector: ThemeDetector!
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

        adapterStore = try await DefaultAdapterStore.createInMemory()

        detector = ThemeDetector(
            adapterStore: adapterStore,
            requestHandler: requestHandler
        )
    }

    // MARK: - Theme Detection Tests

    func testDetectThemeWithMatchingMetaGenerator() async throws {
        // Install a theme with metaGenerator detection
        let theme = ThemeAdapter(
            id: "theme.wp-manga",
            name: "WP Manga",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                metaGenerator: "WordPress.*",
                minScore: 25
            ),
            selectors: makeTestSelectors()
        )
        try await installTheme(theme)

        // Create HTML with WordPress meta generator
        let html = """
            <html><head>
            <meta name="generator" content="WordPress 6.4">
            </head><body></body></html>
            """

        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        XCTAssertEqual(result.theme.id, "theme.wp-manga")
        XCTAssertGreaterThanOrEqual(result.score, 25)
        XCTAssertTrue(result.matchedSignals.contains("metaGenerator"))
    }

    func testDetectThemeWithMatchingSelectors() async throws {
        let theme = ThemeAdapter(
            id: "theme.custom",
            name: "Custom Theme",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                selectors: [".manga-reader", ".chapter-list"],
                minScore: 20
            ),
            selectors: makeTestSelectors()
        )
        try await installTheme(theme)

        let html = """
            <html><body>
            <div class="manga-reader">Content</div>
            <div class="chapter-list">Chapters</div>
            </body></html>
            """

        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        XCTAssertEqual(result.theme.id, "theme.custom")
        XCTAssertGreaterThanOrEqual(result.score, 30)  // 15 * 2 selectors
        XCTAssertTrue(result.matchedSignals.contains("selector:.manga-reader"))
        XCTAssertTrue(result.matchedSignals.contains("selector:.chapter-list"))
    }

    func testDetectThemeWithScriptSrc() async throws {
        let theme = ThemeAdapter(
            id: "theme.script",
            name: "Script Theme",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                scriptSrc: ["wp-includes/js/"],
                minScore: 15
            ),
            selectors: makeTestSelectors()
        )
        try await installTheme(theme)

        let html = """
            <html><head>
            <script src="/wp-includes/js/jquery.js"></script>
            </head><body></body></html>
            """

        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        XCTAssertEqual(result.theme.id, "theme.script")
        XCTAssertGreaterThanOrEqual(result.score, 20)
        XCTAssertTrue(result.matchedSignals.contains(where: { $0.hasPrefix("scriptSrc:") }))
    }

    func testDetectThemeNoMatchReturnsError() async throws {
        let theme = ThemeAdapter(
            id: "theme.specific",
            name: "Specific Theme",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                metaGenerator: "SpecificCMS",
                minScore: 30
            ),
            selectors: makeTestSelectors()
        )
        try await installTheme(theme)

        let html = """
            <html><head>
            <meta name="generator" content="WordPress">
            </head><body></body></html>
            """

        do {
            _ = try await detector.detectTheme(from: html, baseURL: "https://example.org")
            XCTFail("Expected noThemeMatched error")
        } catch let error as ThemeDetectorError {
            XCTAssertEqual(error, .noThemeMatched)
        }
    }

    func testDetectThemeMultipleMatchesReturnsHighestScore() async throws {
        let theme1 = ThemeAdapter(
            id: "theme.low",
            name: "Low Score",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                selectors: [".generic"],
                minScore: 10
            ),
            selectors: makeTestSelectors()
        )

        let theme2 = ThemeAdapter(
            id: "theme.high",
            name: "High Score",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                selectors: [".specific", ".another"],
                minScore: 10
            ),
            selectors: makeTestSelectors()
        )

        try await installTheme(theme1)
        try await installTheme(theme2)

        let html = """
            <html><body>
            <div class="generic">Generic</div>
            <div class="specific">Specific</div>
            <div class="another">Another</div>
            </body></html>
            """

        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        // theme2 should win with 30 points vs 15
        XCTAssertEqual(result.theme.id, "theme.high")
        XCTAssertGreaterThan(result.score, 15)
    }

    func testDetectThemeBelowMinScoreReturnsError() async throws {
        let theme = ThemeAdapter(
            id: "theme.highmin",
            name: "High Min Score",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                selectors: [".generic"],
                minScore: 50
            ),
            selectors: makeTestSelectors()
        )
        try await installTheme(theme)

        let html = """
            <html><body><div class="generic">Test</div></body></html>
            """

        do {
            _ = try await detector.detectTheme(from: html, baseURL: "https://example.org")
            XCTFail("Expected noThemeMatched error")
        } catch let error as ThemeDetectorError {
            XCTAssertEqual(error, .noThemeMatched)
        }
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

extension ThemeDetectorTests {
    func testTieBreakPrefersLexicographicallySmallerID() async throws {
        let beta = ThemeAdapter(
            id: "theme.beta",
            name: "Beta",
            version: "1.0.0",
            detectionSignature: ThemeSignature(selectors: [".same"], minScore: 10),
            selectors: makeTestSelectors()
        )
        let alpha = ThemeAdapter(
            id: "theme.alpha",
            name: "Alpha",
            version: "1.0.0",
            detectionSignature: ThemeSignature(selectors: [".same"], minScore: 10),
            selectors: makeTestSelectors()
        )

        // Install in reverse lexicographic order: the store order must not win.
        try await installTheme(beta)
        try await installTheme(alpha)

        let html = #"<html><body><div class="same">Synthetic</div></body></html>"#
        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        XCTAssertEqual(result.theme.id, "theme.alpha")
    }

    func testTieBreakPrefersHigherMinScore() async throws {
        let low = ThemeAdapter(
            id: "theme.alpha",
            name: "Low minimum",
            version: "1.0.0",
            detectionSignature: ThemeSignature(selectors: [".a", ".b"], minScore: 10),
            selectors: makeTestSelectors()
        )
        let high = ThemeAdapter(
            id: "theme.beta",
            name: "High minimum",
            version: "1.0.0",
            detectionSignature: ThemeSignature(selectors: [".a", ".b"], minScore: 20),
            selectors: makeTestSelectors()
        )

        try await installTheme(low)
        try await installTheme(high)

        let html = #"<html><body><div class="a">A</div><div class="b">B</div></body></html>"#
        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        XCTAssertEqual(result.theme.id, "theme.beta")
    }

    func testTieBreakPrefersAdapterWithMoreSelectors() async throws {
        let selectors = ThemeAdapter(
            id: "theme.selectors",
            name: "Two selectors",
            version: "1.0.0",
            detectionSignature: ThemeSignature(selectors: [".a", ".b"], minScore: 10),
            selectors: makeTestSelectors()
        )
        let generator = ThemeAdapter(
            id: "theme.generator",
            name: "Meta generator",
            version: "1.0.0",
            detectionSignature: ThemeSignature(metaGenerator: "Synthetic", minScore: 10),
            selectors: makeTestSelectors()
        )

        try await installTheme(selectors)
        try await installTheme(generator)

        let html = """
            <html><head><meta name="generator" content="Synthetic CMS"></head>
            <body><div class="a">A</div><div class="b">B</div></body></html>
            """
        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        XCTAssertEqual(result.theme.id, "theme.selectors")
    }

    func testDetectThemeRejectsInvalidURL() async throws {
        do {
            _ = try await detector.detectTheme(for: "://not-a-url")
            XCTFail("Expected invalidURL")
        } catch let error as ThemeDetectorError {
            XCTAssertEqual(error, .invalidURL("://not-a-url"))
        }
    }

    func testInvalidRegexDoesNotAbortScoring() async throws {
        let theme = ThemeAdapter(
            id: "theme.invalid-regex",
            name: "Invalid regex",
            version: "1.0.0",
            detectionSignature: ThemeSignature(
                metaGenerator: "[",
                selectors: [".present"],
                minScore: 10
            ),
            selectors: makeTestSelectors()
        )
        try await installTheme(theme)

        let html = #"""
            <html>
            <head><meta name="generator" content="Synthetic"></head>
            <body><div class="present">Text</div></body>
            </html>
            """#
        let result = try await detector.detectTheme(from: html, baseURL: "https://example.org")

        XCTAssertEqual(result.theme.id, "theme.invalid-regex")
        XCTAssertEqual(result.score, 15)
    }
}
