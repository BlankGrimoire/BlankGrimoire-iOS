// SPDX-License-Identifier: MPL-2.0

import XCTest
import ReaderCore

final class ContractTests: XCTestCase {
    
    var fixturesURL: URL!
    var schemaURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Locate fixtures and schema from SDK sync
        let bundle = Bundle(for: ContractTests.self)
        let resourcesURL = bundle.resourceURL?.deletingLastPathComponent().deletingLastPathComponent()
        
        if let resourcesURL = resourcesURL {
            self.fixturesURL = resourcesURL
                .appendingPathComponent("BlankGrimoire")
                .appendingPathComponent("Resources")
                .appendingPathComponent("Contract")
                .appendingPathComponent("fixtures")
                .appendingPathComponent("v1")
            
            self.schemaURL = resourcesURL
                .appendingPathComponent("BlankGrimoire")
                .appendingPathComponent("Resources")
                .appendingPathComponent("Contract")
                .appendingPathComponent("schema-v1.json")
        }
    }
    
    // MARK: - Fixture Decoding Tests
    
    func testDecodeMangaSummary() throws {
        let data = try fixtureData("manga-summary.json")
        let result = try JSONDecoder().decode(PagedResult<MangaSummary>.self, from: data)
        
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].key, "lorem-ipsum")
        XCTAssertEqual(result.items[0].title, "Lorem Ipsum")
        XCTAssertEqual(result.items[0].coverURL, "https://example.org/covers/lorem-ipsum.jpg")
        XCTAssertEqual(result.items[1].key, "dolor-sit")
        XCTAssertEqual(result.items[1].title, "Dolor Sit")
        XCTAssertNil(result.items[1].coverURL)
        XCTAssertTrue(result.hasNextPage)
    }
    
    func testDecodeMangaDetails() throws {
        let data = try fixtureData("manga-details.json")
        let details = try JSONDecoder().decode(MangaDetails.self, from: data)
        
        XCTAssertEqual(details.key, "lorem-ipsum")
        XCTAssertEqual(details.title, "Lorem Ipsum")
        XCTAssertEqual(details.coverURL, "https://example.org/covers/lorem-ipsum.jpg")
        XCTAssertEqual(details.altTitles, ["Lorem", "Ipsum Dolor"])
        XCTAssertEqual(details.authors, ["Author One"])
        XCTAssertEqual(details.artists, ["Artist One"])
        XCTAssertEqual(details.synopsis, "Lorem ipsum dolor sit amet.")
        XCTAssertEqual(details.tags, ["action", "fantasy"])
        XCTAssertEqual(details.status, .ongoing)
        XCTAssertEqual(details.contentRating, .safe)
        XCTAssertNotNil(details.attribution)
        XCTAssertEqual(details.attribution?.siteName, "Example Library")
    }
    
    func testDecodeMangaDetailsUnknownStatus() throws {
        let data = try fixtureData("manga-details-unknown-status.json")
        let details = try JSONDecoder().decode(MangaDetails.self, from: data)
        
        XCTAssertEqual(details.key, "lorem-ipsum")
        XCTAssertEqual(details.title, "Lorem Ipsum")
        XCTAssertEqual(details.status, .unknown)
        XCTAssertEqual(details.contentRating, .unknown)
    }
    
    func testDecodeChapter() throws {
        let data = try fixtureData("chapter.json")
        let chapter = try JSONDecoder().decode(Chapter.self, from: data)
        
        XCTAssertEqual(chapter.key, "https://example.org/series/lorem/chapter-1")
        XCTAssertEqual(chapter.title, "Chapter 1: The Beginning")
        XCTAssertEqual(chapter.number, 1)
        XCTAssertEqual(chapter.volume, 1)
        XCTAssertEqual(chapter.language, "en")
        XCTAssertEqual(chapter.publishedAt, "2024-01-15T12:00:00Z")
        XCTAssertEqual(chapter.group, "Example Group")
    }
    
    func testDecodePage() throws {
        let data = try fixtureData("page.json")
        let page = try JSONDecoder().decode(Page.self, from: data)
        
        XCTAssertEqual(page.index, 0)
        XCTAssertEqual(page.imageURL, "https://example.org/images/lorem-ipsum/12-5/001.jpg")
        XCTAssertEqual(page.headers?["Referer"], "https://example.org/")
    }
    
    func testDecodeSearchQuery() throws {
        let data = try fixtureData("search-query.json")
        let query = try JSONDecoder().decode(SearchQuery.self, from: data)
        
        XCTAssertEqual(query.text, "lorem")
        XCTAssertEqual(query.page, 1)
        XCTAssertEqual(query.filters?["status"], "ongoing")
    }
    
    func testDecodeThemeSignature() throws {
        let data = try fixtureData("theme-signature.json")
        let signature = try JSONDecoder().decode(ThemeSignature.self, from: data)
        
        XCTAssertEqual(signature.metaGenerator, "^ExampleCMS")
        XCTAssertEqual(signature.selectors, [".example-reader", ".example-chapter-list"])
        XCTAssertEqual(signature.scriptSrc, ["/assets/example-theme\\.js"])
        XCTAssertEqual(signature.probePaths, ["/example-feed.json"])
        XCTAssertEqual(signature.minScore, 5)
    }
    
    func testDecodeThemeSelectors() throws {
        let data = try fixtureData("theme-selectors.json")
        let selectors = try JSONDecoder().decode(ThemeSelectors.self, from: data)
        
        XCTAssertEqual(selectors.search.path, "/search")
        XCTAssertEqual(selectors.search.item, ".result")
        XCTAssertEqual(selectors.search.title, ".result-title")
        XCTAssertEqual(selectors.search.link, "a")
        XCTAssertEqual(selectors.search.cover, "img")
        XCTAssertEqual(selectors.search.nextPage, ".next")
        
        XCTAssertEqual(selectors.details.title, "h1.series-title")
        XCTAssertEqual(selectors.details.cover, ".series-cover img")
        XCTAssertEqual(selectors.details.synopsis, ".series-synopsis")
        
        XCTAssertEqual(selectors.chapters.item, ".chapter")
        XCTAssertEqual(selectors.chapters.link, "a")
        XCTAssertEqual(selectors.chapters.order, "desc")
        
        XCTAssertEqual(selectors.pages.strategies.count, 1)
        if case .css(let cssStrategy) = selectors.pages.strategies[0] {
            XCTAssertEqual(cssStrategy.image, ".reader img")
            XCTAssertEqual(cssStrategy.srcAttributes, ["data-src", "src"])
        } else {
            XCTFail("Expected CSS strategy")
        }
    }
    
    func testDecodeThemeSelectorsOverrides() throws {
        let data = try fixtureData("theme-selectors-overrides.json")
        let overrides = try JSONDecoder().decode(ThemeSelectorsOverrides.self, from: data)
        
        XCTAssertEqual(overrides.search?.title, ".custom-result-title")
        XCTAssertEqual(overrides.details?.status, ".custom-status")
        XCTAssertEqual(overrides.pages?.strategies.count, 1)
        if case .css(let cssStrategy) = overrides.pages?.strategies[0] {
            XCTAssertEqual(cssStrategy.image, ".custom-reader img")
            XCTAssertEqual(cssStrategy.srcAttributes, ["data-src"])
        }
    }
    
    func testDecodeThemeAdapter() throws {
        let data = try fixtureData("theme-adapter.json")
        let adapter = try JSONDecoder().decode(ThemeAdapter.self, from: data)
        
        XCTAssertEqual(adapter.id, "theme.example")
        XCTAssertEqual(adapter.name, "Example Theme")
        XCTAssertEqual(adapter.version, "1.0.0")
        XCTAssertEqual(adapter.apiVersion, 1)
        XCTAssertEqual(adapter.detectionSignature.minScore, 2)
        XCTAssertEqual(adapter.selectors.search.path, "/search")
    }
    
    func testDecodeAdapterManifest() throws {
        let data = try fixtureData("manifest.json")
        let manifest = try JSONDecoder().decode(AdapterManifest.self, from: data)
        
        XCTAssertEqual(manifest.id, "theme.example")
        XCTAssertEqual(manifest.name, "Example Theme")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.apiVersion, 1)
        XCTAssertEqual(manifest.detectionSignature.minScore, 5)
        XCTAssertEqual(manifest.sha256.count, 64)
    }
    
    func testDecodeRepositoryIndex() throws {
        let data = try fixtureData("repository-index.json")
        let index = try JSONDecoder().decode(RepositoryIndex.self, from: data)
        
        XCTAssertEqual(index.formatVersion, 1)
        XCTAssertEqual(index.name, "Example Repository")
        XCTAssertTrue(index.publicKey.hasPrefix("ed25519:"))
        XCTAssertEqual(index.extensions.count, 1)
        XCTAssertEqual(index.extensions[0].id, "theme.example")
        XCTAssertEqual(index.extensions[0].apiVersion, 1)
        XCTAssertEqual(index.extensions[0].sha256.count, 64)
    }
    
    func testDecodeSiteContext() throws {
        let data = try fixtureData("site-context.json")
        let context = try JSONDecoder().decode(SiteContext.self, from: data)
        
        XCTAssertEqual(context.baseURL, "https://example.org/")
        XCTAssertEqual(context.siteName, "Example Library")
        XCTAssertEqual(context.overrides.search, nil)
    }
    
    func testDecodeExtractionStrategy() throws {
        let data = try fixtureData("extraction-strategy.json")
        let strategy = try JSONDecoder().decode(ExtractionStrategy.self, from: data)
        
        if case .css(let css) = strategy {
            XCTAssertEqual(css.image, ".reader img")
            XCTAssertEqual(css.srcAttributes, ["data-src", "src"])
            XCTAssertEqual(css.headers?["Referer"], "https://example.org/")
        } else {
            XCTFail("Expected CSS strategy")
        }
    }
    
    func testDecodePagesConfig() throws {
        let data = try fixtureData("pages-config.json")
        let config = try JSONDecoder().decode(ThemeSelectors.PagesConfig.self, from: data)
        
        XCTAssertEqual(config.strategies.count, 2)
        if case .css(let css) = config.strategies[0] {
            XCTAssertEqual(css.image, ".reader img")
        }
        if case .scriptJSON(let script) = config.strategies[1] {
            XCTAssertEqual(script.pattern, "window.__PAGES__")
            XCTAssertEqual(script.path, "pages")
        }
    }
    
    func testDecodeHttpRequestResponse() throws {
        let requestData = try fixtureData("http-request.json")
        let request = try JSONDecoder().decode(HttpRequest.self, from: requestData)
        
        XCTAssertEqual(request.url, "https://example.org/search?q=lorem")
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.headers?["Accept"], "text/html")
        
        let responseData = try fixtureData("http-response.json")
        let response = try JSONDecoder().decode(HttpResponse.self, from: responseData)
        
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.url, "https://example.org/search?q=lorem")
        XCTAssertEqual(response.headers["content-type"], "text/html")
    }
    
    func testDecodeAttribution() throws {
        let data = try fixtureData("attribution.json")
        let attribution = try JSONDecoder().decode(Attribution.self, from: data)
        
        XCTAssertEqual(attribution.siteName, "Example Library")
        XCTAssertEqual(attribution.siteURL, "https://example.org/")
        XCTAssertEqual(attribution.logoURL, "https://example.org/logo.png")
        XCTAssertEqual(attribution.credits, "Lorem ipsum credits")
    }
    
    // MARK: - Negative Tests
    
    func testRejectUnknownStatus() throws {
        let details = try JSONDecoder().decode(MangaDetails.self, from: fixtureData("manga-details.json"))
        let modifiedDetails = MangaDetails(
            key: details.key,
            title: details.title,
            coverURL: details.coverURL,
            altTitles: details.altTitles,
            authors: details.authors,
            artists: details.artists,
            synopsis: details.synopsis,
            tags: details.tags,
            status: MangaStatus(rawValue: "something-new") ?? .unknown,
            contentRating: details.contentRating,
            attribution: details.attribution
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(modifiedDetails)
        
        // Decoding should fail for unknown status
        XCTAssertThrowsError(try JSONDecoder().decode(MangaDetails.self, from: data)) { error in
            // Should fail because "something-new" is not in enum
        }
    }
    
    func testRejectUnknownContentRating() throws {
        let details = try JSONDecoder().decode(MangaDetails.self, from: fixtureData("manga-details.json"))
        let modifiedDetails = MangaDetails(
            key: details.key,
            title: details.title,
            coverURL: details.coverURL,
            altTitles: details.altTitles,
            authors: details.authors,
            artists: details.artists,
            synopsis: details.synopsis,
            tags: details.tags,
            status: details.status,
            contentRating: ContentRating(rawValue: "explicit") ?? .unknown,
            attribution: details.attribution
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(modifiedDetails)
        
        XCTAssertThrowsError(try JSONDecoder().decode(MangaDetails.self, from: data))
    }
    
    func testRejectLegacyManifestSignature() throws {
        // Legacy manifest with 'signature' instead of 'detectionSignature'
        let json = """
        {
            "id": "theme.example",
            "name": "Example",
            "version": "1.0.0",
            "apiVersion": 1,
            "signature": { "minScore": 1 },
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
        }
        """
        
        XCTAssertThrowsError(try JSONDecoder().decode(AdapterManifest.self, from: json.data(using: .utf8)!))
    }
    
    func testRejectUnsupportedApiVersion() throws {
        let manifest = try JSONDecoder().decode(AdapterManifest.self, from: fixtureData("manifest.json"))
        let modifiedManifest = AdapterManifest(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            apiVersion: 2,
            detectionSignature: manifest.detectionSignature,
            sha256: manifest.sha256
        )
        
        let data = try JSONEncoder().encode(modifiedManifest)
        
        XCTAssertThrowsError(try JSONDecoder().decode(AdapterManifest.self, from: data))
    }
    
    func testRejectInvalidSha256() throws {
        let manifest = try JSONDecoder().decode(AdapterManifest.self, from: fixtureData("manifest.json"))
        let modifiedManifest = AdapterManifest(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            apiVersion: manifest.apiVersion,
            detectionSignature: manifest.detectionSignature,
            sha256: "xyz"
        )
        
        let data = try JSONEncoder().encode(modifiedManifest)
        
        XCTAssertThrowsError(try JSONDecoder().decode(AdapterManifest.self, from: data))
    }
    
    func testRejectInvalidRepositoryIndexSignature() throws {
        let json = """
        {
            "formatVersion": 1,
            "name": "Test",
            "publicKey": "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "extensions": [{
                "id": "theme.test",
                "name": "Test",
                "version": "1.0.0",
                "apiVersion": 1,
                "bundleURL": "test.js",
                "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
                "bundleSignature": "invalid"
            }]
        }
        """
        
        XCTAssertThrowsError(try JSONDecoder().decode(RepositoryIndex.self, from: json.data(using: .utf8)!))
    }
    
    // MARK: - Helpers
    
    private func fixtureData(_ filename: String) throws -> Data {
        let url = fixturesURL.appendingPathComponent(filename)
        return try Data(contentsOf: url)
    }
}