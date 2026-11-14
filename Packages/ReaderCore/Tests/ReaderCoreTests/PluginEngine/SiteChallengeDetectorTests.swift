// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

final class SiteChallengeDetectorTests: XCTestCase {
    func testDetectsChallengeBodyWithSuccessfulStatus() {
        XCTAssertTrue(
            SiteChallengeDetector.isChallenge(
                status: 200,
                body: "<html><title>Just a moment...</title><div id=\"cf-chl-widget\"></div></html>"
            )
        )
    }

    func testDetectsForbiddenStatus() {
        XCTAssertTrue(SiteChallengeDetector.isChallenge(status: 403, body: "blocked"))
    }

    func testDoesNotRejectNormalHTML() {
        XCTAssertFalse(
            SiteChallengeDetector.isChallenge(
                status: 200,
                body: "<html><main><h1>Example Series</h1></main></html>"
            )
        )
    }
}
