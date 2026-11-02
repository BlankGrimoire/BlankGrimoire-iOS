// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import XCTest

final class JSPluginRuntimeTests: XCTestCase {

    // MARK: - Loading

    func testVendoredRuntimeResourceIsAvailable() throws {
        let script = try PluginRuntimeResources.runtimeScript()

        XCTAssertTrue(script.contains("BlankGrimoireRuntime"))
        XCTAssertTrue(script.contains("__apiVersion"))
        XCTAssertEqual(JSPluginRuntime.supportedAPIVersion, 1)
    }

    func testLoadsRuntimeAndAdapterMetadata() throws {
        let runtime = try makeRuntime()

        XCTAssertEqual(runtime.adapterID, "theme.example")
        XCTAssertEqual(runtime.adapterVersion, "1.0.0")
        XCTAssertEqual(runtime.adapterAPIVersion, 1)
    }

    func testRejectsRuntimeAPIVersionMismatch() {
        let fakeRuntime = #"var BlankGrimoireRuntime = { __apiVersion: 2, dispatch: function () {} };"#

        XCTAssertThrowsError(
            try JSPluginRuntime(
                runtimeScript: fakeRuntime,
                adapterScript: adapterScript()
            )
        ) { error in
            XCTAssertEqual(error as? PluginEngineError, .apiVersionMismatch(expected: 1, found: 2))
        }
    }

    func testRejectsRuntimeWithoutDispatch() {
        let fakeRuntime = #"var BlankGrimoireRuntime = { __apiVersion: 1 };"#

        XCTAssertThrowsError(
            try JSPluginRuntime(
                runtimeScript: fakeRuntime,
                adapterScript: adapterScript()
            )
        ) { error in
            XCTAssertEqual(
                error as? PluginEngineError,
                .runtimeLoadFailed("The runtime does not expose dispatch")
            )
        }
    }

    func testRejectsAdapterWithoutSelectors() {
        let invalidAdapter = #"var BlankGrimoireRuntime = { default: { id: "theme.example", apiVersion: 1 } };"#

        XCTAssertThrowsError(
            try JSPluginRuntime(
                runtimeScript: PluginRuntimeResources.runtimeScript(),
                adapterScript: invalidAdapter
            )
        ) { error in
            XCTAssertEqual(error as? PluginEngineError, .invalidAdapter("Missing adapter selectors"))
        }
    }

    func testRejectsAdapterAPIVersionMismatch() {
        XCTAssertThrowsError(
            try JSPluginRuntime(
                runtimeScript: PluginRuntimeResources.runtimeScript(),
                adapterScript: adapterScript(apiVersion: 2)
            )
        ) { error in
            XCTAssertEqual(error as? PluginEngineError, .apiVersionMismatch(expected: 1, found: 2))
        }
    }

    func testRejectsManifestMismatch() {
        let manifest = AdapterManifest(
            id: "theme.other",
            name: "Other Theme",
            version: "1.0.0",
            apiVersion: 1,
            detectionSignature: ThemeSignature(minScore: 1),
            sha256: String(repeating: "a", count: 64)
        )

        XCTAssertThrowsError(
            try JSPluginRuntime(
                runtimeScript: PluginRuntimeResources.runtimeScript(),
                adapterScript: adapterScript(),
                manifest: manifest
            )
        ) { error in
            guard let pluginError = error as? PluginEngineError,
                case .invalidManifest = pluginError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - Extraction

    func testSearchDecodesPagedResultAndResolvesURLs() async throws {
        let runtime = try makeRuntime()
        let html = """
            <html><body>
            <div class="result">
              <a href="/titles/lorem-ipsum"><span class="result-title">Lorem Ipsum</span></a>
              <img src="/covers/lorem-ipsum.jpg" alt="">
            </div>
            <div class="result">
              <a href="https://example.org/titles/dolor-sit"><span class="result-title">Dolor Sit</span></a>
            </div>
            <div class="next"></div>
            </body></html>
            """

        let result = try await runtime.search(
            SearchQuery(text: "lorem", page: 1),
            in: page(html)
        )

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.hasNextPage)
        XCTAssertEqual(result.items[0].key, "https://example.org/titles/lorem-ipsum")
        XCTAssertEqual(result.items[0].title, "Lorem Ipsum")
        XCTAssertEqual(result.items[0].coverURL, "https://example.org/covers/lorem-ipsum.jpg")
        XCTAssertEqual(result.items[1].key, "https://example.org/titles/dolor-sit")
        XCTAssertNil(result.items[1].coverURL)
    }

    func testDetailsNormalizesStatusAndContentRating() async throws {
        let runtime = try makeRuntime()
        let html = """
            <html><body>
            <h1 class="series-title">Lorem Ipsum</h1>
            <div class="series-cover"><img src="/covers/lorem-ipsum.jpg"></div>
            <p class="series-synopsis">Lorem ipsum dolor sit amet.</p>
            <span class="series-authors">Lorem Author, Dolor Author</span>
            <span class="series-artists">Ipsum Artist</span>
            <span class="series-alt-titles">Dolor Sit Amet | Consectetur</span>
            <span class="series-tags">lorem, ipsum</span>
            <span class="series-status">Ongoing</span>
            <span class="series-rating">Safe</span>
            <div class="site-logo"><img src="/logo.png"></div>
            <p class="site-credits">Lorem credits</p>
            </body></html>
            """

        let details = try await runtime.details(
            for: "https://example.org/titles/lorem-ipsum",
            in: page(html)
        )

        XCTAssertEqual(details.key, "https://example.org/titles/lorem-ipsum")
        XCTAssertEqual(details.title, "Lorem Ipsum")
        XCTAssertEqual(details.coverURL, "https://example.org/covers/lorem-ipsum.jpg")
        XCTAssertEqual(details.synopsis, "Lorem ipsum dolor sit amet.")
        XCTAssertEqual(details.authors, ["Lorem Author", "Dolor Author"])
        XCTAssertEqual(details.artists, ["Ipsum Artist"])
        XCTAssertEqual(details.altTitles, ["Dolor Sit Amet", "Consectetur"])
        XCTAssertEqual(details.tags, ["lorem", "ipsum"])
        XCTAssertEqual(details.status, .ongoing)
        XCTAssertEqual(details.contentRating, .safe)
        XCTAssertEqual(details.attribution?.siteName, "Example Library")
        XCTAssertEqual(details.attribution?.siteURL, "https://example.org")
        XCTAssertEqual(details.attribution?.logoURL, "https://example.org/logo.png")
        XCTAssertEqual(details.attribution?.credits, "Lorem credits")
    }

    func testChaptersPreserveOrderAndParseDates() async throws {
        let runtime = try makeRuntime()
        let html = """
            <html><body>
            <div class="chapter">
              <a href="/titles/lorem-ipsum/chapter-1">Chapter 1</a>
              <span class="chapter-title">Chapter 1</span>
              <span class="chapter-date">2026-01-01T10:00:00Z</span>
            </div>
            <div class="chapter">
              <a href="/titles/lorem-ipsum/chapter-2">Chapter 2</a>
              <span class="chapter-title">Chapter 2</span>
              <span class="chapter-date">2026-01-02T10:00:00Z</span>
            </div>
            </body></html>
            """

        let chapters = try await runtime.chapters(
            for: "https://example.org/titles/lorem-ipsum",
            in: page(html)
        )

        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].key, "https://example.org/titles/lorem-ipsum/chapter-2")
        XCTAssertEqual(chapters[0].title, "Chapter 2")
        XCTAssertEqual(chapters[0].number, 2)
        XCTAssertEqual(chapters[0].publishedAt, "2026-01-02T10:00:00.000Z")
        XCTAssertEqual(chapters[1].key, "https://example.org/titles/lorem-ipsum/chapter-1")
        XCTAssertEqual(chapters[1].number, 1)
    }

    func testPagesResolveRelativeImageURLsAndHeaders() async throws {
        let runtime = try makeRuntime()
        let html = """
            <html><body>
            <div class="reader">
              <img data-src="/images/page-1.jpg" src="/placeholder.jpg">
              <img src="/images/page-2.jpg">
            </div>
            </body></html>
            """

        let pages = try await runtime.pages(
            mangaKey: "https://example.org/titles/lorem-ipsum",
            chapterKey: "https://example.org/titles/lorem-ipsum/chapter-2",
            in: page(html)
        )

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].index, 0)
        XCTAssertEqual(pages[0].imageURL, "https://example.org/images/page-1.jpg")
        XCTAssertEqual(pages[0].headers, ["Referer": "https://example.org/"])
        XCTAssertEqual(pages[1].index, 1)
        XCTAssertEqual(pages[1].imageURL, "https://example.org/images/page-2.jpg")
    }

    func testRawInvokeReturnsJSONString() async throws {
        let runtime = try makeRuntime()
        let html = """
            <html><body><h1 class="series-title">Lorem Ipsum</h1></body></html>
            """

        let json = try await runtime.invoke(
            method: "details",
            argumentsJSON: #"{"key":"https://example.org/titles/lorem-ipsum"}"#,
            in: page(html)
        )

        XCTAssertTrue(json.contains(#""title":"Lorem Ipsum""#))
        XCTAssertTrue(json.contains(#""status":"unknown""#))
    }

    func testUnknownMethodThrowsDispatchError() async throws {
        let runtime = try makeRuntime()

        do {
            _ = try await runtime.invoke(
                method: "missingMethod",
                in: page("<html><body></body></html>")
            )
            XCTFail("Expected a dispatch error")
        } catch let error as PluginEngineError {
            guard case .dispatchFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Unknown adapter method"))
        }
    }

    func testAjaxStrategyUsesRequestHandlerAndNativeParser() async throws {
        let recorder = RequestRecorder()
        let ajaxStrategy = #"""
            {
              "kind": "ajax",
              "path": "/api/pages",
              "method": "GET",
              "then": {
                "kind": "css",
                "image": ".reader img",
                "srcAttributes": ["src"]
              }
            }
            """#
        let runtime = try makeRuntime(
            pagesStrategy: ajaxStrategy,
            requestHandler: { request in
                await recorder.record(request)
                return HttpResponse(
                    status: 200,
                    url: request.url,
                    headers: ["Content-Type": "text/html"],
                    body: #"<html><body><div class="reader"><img src="/images/ajax-1.jpg"></div></body></html>"#
                )
            }
        )

        let pages = try await runtime.pages(
            mangaKey: "https://example.org/titles/lorem-ipsum",
            chapterKey: "https://example.org/titles/lorem-ipsum/chapter-2",
            in: page("<html><body></body></html>")
        )

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].imageURL, "https://example.org/images/ajax-1.jpg")

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, "https://example.org/api/pages")
        XCTAssertEqual(requests.first?.method, "GET")
    }

    func testDisposeRejectsLaterCalls() async throws {
        let runtime = try makeRuntime()
        await runtime.dispose()

        do {
            _ = try await runtime.invoke(
                method: "details",
                in: page("<html><body></body></html>")
            )
            XCTFail("Expected a disposed error")
        } catch let error as PluginEngineError {
            XCTAssertEqual(error, .disposed)
        }
    }

    // MARK: - Helpers

    private func makeRuntime(
        manifest: AdapterManifest? = nil,
        pagesStrategy: String? = nil,
        requestHandler: PluginRequestHandler? = nil
    ) throws -> JSPluginRuntime {
        try JSPluginRuntime(
            runtimeScript: PluginRuntimeResources.runtimeScript(),
            adapterScript: adapterScript(pagesStrategy: pagesStrategy ?? defaultPagesStrategy),
            manifest: manifest,
            requestHandler: requestHandler
        )
    }

    private func adapterScript(
        id: String = "theme.example",
        version: String = "1.0.0",
        apiVersion: Int = 1,
        pagesStrategy: String? = nil
    ) -> String {
        """
        var BlankGrimoireRuntime = {
          default: {
            id: "\(id)",
            name: "Example Theme",
            version: "\(version)",
            apiVersion: \(apiVersion),
            selectors: {
              search: {
                path: "/search",
                item: ".result",
                title: ".result-title",
                link: "a",
                cover: "img",
                nextPage: ".next"
              },
              details: {
                title: "h1.series-title",
                cover: ".series-cover img",
                synopsis: ".series-synopsis",
                authors: ".series-authors",
                artists: ".series-artists",
                altTitles: ".series-alt-titles",
                tags: ".series-tags",
                status: ".series-status",
                contentRating: ".series-rating"
              },
              chapters: {
                item: ".chapter",
                link: "a",
                title: ".chapter-title",
                date: ".chapter-date",
                order: "desc"
              },
              pages: {
                strategies: [\(pagesStrategy ?? defaultPagesStrategy)]
              },
              attribution: {
                logo: ".site-logo img",
                credits: ".site-credits"
              }
            }
          }
        };
        """
    }

    private func page(
        _ html: String,
        baseURL: String = "https://example.org",
        siteName: String = "Example Library"
    ) -> PluginPageContext {
        PluginPageContext(html: html, baseURL: baseURL, siteName: siteName)
    }

    private var defaultPagesStrategy: String {
        #"{"kind":"css","image":".reader img","srcAttributes":["data-src","src"],"headers":{"Referer":"https://example.org/"}}"#
    }

    private actor RequestRecorder {
        private(set) var requests: [HttpRequest] = []

        func record(_ request: HttpRequest) {
            requests.append(request)
        }
    }
}
