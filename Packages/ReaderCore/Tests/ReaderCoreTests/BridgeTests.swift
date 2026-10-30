// SPDX-License-Identifier: MPL-2.0

import XCTest
import ReaderCore
import os

final class NativeBridgeTests: XCTestCase {
    
    var bridge: NativeBridgeImpl!
    
    override func setUp() async throws {
        try await super.setUp()
        bridge = NativeBridgeImpl(allowedHosts: ["example.org", "127.0.0.1"])
    }
    
    override func tearDown() async throws {
        bridge = nil
        try await super.tearDown()
    }
    
    // MARK: - Allowlist Tests
    
    func testAllowExactHost() {
        XCTAssertTrue(bridge.isAllowed("https://example.org/"))
        XCTAssertTrue(bridge.isAllowed("http://example.org/path"))
    }
    
    func testAllowSubdomain() {
        XCTAssertTrue(bridge.isAllowed("https://www.example.org/"))
        XCTAssertTrue(bridge.isAllowed("https://api.example.org/v1"))
    }
    
    func testRejectDifferentDomain() {
        XCTAssertFalse(bridge.isAllowed("https://example.com/"))
        XCTAssertFalse(bridge.isAllowed("https://evil.example.org/"))
    }
    
    func testAllowLoopback() {
        XCTAssertTrue(bridge.isAllowed("http://127.0.0.1:8080/"))
        XCTAssertTrue(bridge.isAllowed("http://127.0.0.1/path"))
    }
    
    func testCaseInsensitive() {
        XCTAssertTrue(bridge.isAllowed("https://EXAMPLE.ORG/"))
        XCTAssertTrue(bridge.isAllowed("https://Example.Org/path"))
    }
    
    // MARK: - HTML Parsing Tests
    
    func testParseHTML() async throws {
        let html = """
        <html>
            <head><title>Test Page</title></head>
            <body>
                <h1 id="title">Hello World</h1>
                <div class="content">
                    <p class="text">Lorem ipsum</p>
                </div>
            </body>
        </html>
        """
        
        let parsed = try await bridge.parseHTML(html)
        
        XCTAssertFalse(parsed.documentId.isEmpty)
        XCTAssertEqual(parsed.title, "Test Page")
    }
    
    func testQuerySelector() async throws {
        let html = """
        <html><body>
            <h1 id="title">Title</h1>
            <div class="content">Content</div>
        </body></html>
        """
        
        let parsed = try await bridge.parseHTML(html)
        
        let element = try await bridge.querySelector(documentId: parsed.documentId, selector: "#title")
        XCTAssertNotNil(element)
        XCTAssertEqual(element?.textContent, "Title")
        
        let elements = try await bridge.querySelectorAll(documentId: parsed.documentId, selector: "div")
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].textContent, "Content")
    }
    
    func testQuerySelectorNotFound() async throws {
        let html = "<html><body><div>Test</div></body></html>"
        let parsed = try await bridge.parseHTML(html)
        
        let element = try await bridge.querySelector(documentId: parsed.documentId, selector: ".nonexistent")
        XCTAssertNil(element)
    }
    
    func testGetAttribute() async throws {
        let html = "<html><body><a id='link' href='/page' class='btn'>Link</a></body></html>"
        let parsed = try await bridge.parseHTML(html)
        
        let element = try await bridge.querySelector(documentId: parsed.documentId, selector: "#link")
        XCTAssertNotNil(element)
        
        let href = try await bridge.getAttribute(elementId: element!.elementId, name: "href")
        XCTAssertEqual(href, "/page")
        
        let className = try await bridge.getAttribute(elementId: element!.elementId, name: "class")
        XCTAssertEqual(className, "btn")
    }
    
    func testGetTextContent() async throws {
        let html = "<html><body><p id='text'>Hello <strong>World</strong></p></body></html>"
        let parsed = try await bridge.parseHTML(html)
        
        let element = try await bridge.querySelector(documentId: parsed.documentId, selector: "#text")
        let text = try await bridge.getTextContent(elementId: element!.elementId)
        XCTAssertEqual(text, "Hello World")
    }
    
    // MARK: - Timer Tests
    
    func testSetTimeout() async throws {
        let expectation = XCTestExpectation(description: "Timer fired")
        
        let id = bridge.setTimeout({
            expectation.fulfill()
        }, 10)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Timer should be cleaned up - we can't directly test internal state,
        // but we can verify the timer doesn't fire again
    }
    
    func testClearTimeout() {
        let fired = OSAllocatedUnfairLock(initialState: false)
        
        let id = bridge.setTimeout({
            fired.withLock { $0 = true }
        }, 10)
        
        bridge.clearTimeout(id)
        
        let expectation = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertFalse(fired.withLock { $0 })
    }
    
    // MARK: - Scripts Tests
    
    func testGetScripts() async throws {
        let html = """
        <html><head>
            <script>var a = 1;</script>
            <script src="/script.js"></script>
            <script>function test() { return 42; }</script>
        </head><body></body></html>
        """
        
        let parsed = try await bridge.parseHTML(html)
        let scripts = try await bridge.getScripts(documentId: parsed.documentId)
        
        XCTAssertEqual(scripts.count, 2) // Only inline scripts
        XCTAssertTrue(scripts.contains("var a = 1;"))
        XCTAssertTrue(scripts.contains("function test() { return 42; }"))
    }
    
    // MARK: - Document Management Tests
    
    func testReleaseDocument() async throws {
        let html = "<html><body>Test</body></html>"
        let parsed = try await bridge.parseHTML(html)
        
        bridge.releaseDocument(parsed.documentId)
        
        // Should fail to query after release
        do {
            _ = try await bridge.querySelector(documentId: parsed.documentId, selector: "body")
            XCTFail("Should throw documentNotFound")
        } catch BridgeError.documentNotFound {
            // Expected
        }
    }
}