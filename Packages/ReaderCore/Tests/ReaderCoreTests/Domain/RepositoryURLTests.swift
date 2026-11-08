// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

final class RepositoryURLTests: XCTestCase {
    func testAddsHTTPSAndIndexForHostOnly() {
        XCTAssertEqual(
            RepositoryURL.normalizedIndexURL(from: "example.org")?.absoluteString,
            "https://example.org/index.json"
        )
    }

    func testAddsIndexForTrailingSlash() {
        XCTAssertEqual(
            RepositoryURL.normalizedIndexURL(from: "https://example.org/repo/")?.absoluteString,
            "https://example.org/repo/index.json"
        )
    }

    func testKeepsExplicitIndexURL() {
        XCTAssertEqual(
            RepositoryURL.normalizedIndexURL(from: "https://example.org/repo/index.json")?.absoluteString,
            "https://example.org/repo/index.json"
        )
    }

    func testKeepsCustomEndpointPath() {
        XCTAssertEqual(
            RepositoryURL.normalizedIndexURL(from: "https://example.org/repo")?.absoluteString,
            "https://example.org/repo"
        )
    }

    func testKeepsQueryOnExplicitIndexURL() {
        XCTAssertEqual(
            RepositoryURL.normalizedIndexURL(from: "https://example.org/index.json?token=lorem")?.absoluteString,
            "https://example.org/index.json?token=lorem"
        )
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(
            RepositoryURL.normalizedIndexURL(from: "  https://example.org  ")?.absoluteString,
            "https://example.org/index.json"
        )
    }

    func testLowercasesHost() {
        XCTAssertEqual(
            RepositoryURL.normalizedIndexURL(from: "https://EXAMPLE.ORG")?.absoluteString,
            "https://example.org/index.json"
        )
    }

    func testRejectsNonHTTPS() {
        XCTAssertNil(RepositoryURL.normalizedIndexURL(from: "http://example.org/index.json"))
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(RepositoryURL.normalizedIndexURL(from: "   "))
    }

    func testRejectsInputWithoutHost() {
        XCTAssertNil(RepositoryURL.normalizedIndexURL(from: "https://"))
    }
}
