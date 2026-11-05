// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

final class SiteURLTests: XCTestCase {
    func testNormalizesURLWithoutScheme() {
        XCTAssertEqual(
            SiteURL.normalizedURL(from: "example.org/path")?.absoluteString,
            "https://example.org/path"
        )
    }

    func testKeepsHTTPScheme() {
        XCTAssertEqual(
            SiteURL.normalizedURL(from: "http://example.org")?.absoluteString,
            "http://example.org"
        )
    }

    func testBaseURLDropsPathQueryAndFragment() {
        XCTAssertEqual(
            SiteURL.baseURLString(from: "https://example.org/path?q=1#top"),
            "https://example.org"
        )
    }

    func testBaseURLTrimsTrailingSlash() {
        XCTAssertEqual(
            SiteURL.baseURLString(from: "https://example.org/"),
            "https://example.org"
        )
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertNil(SiteURL.normalizedURL(from: "ftp://example.org"))
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(SiteURL.normalizedURL(from: "   "))
    }

    func testRejectsInputWithoutHost() {
        XCTAssertNil(SiteURL.normalizedURL(from: "https://"))
    }

    func testHostIsLowercased() {
        XCTAssertEqual(SiteURL.host(from: "https://EXAMPLE.ORG"), "example.org")
    }
}
