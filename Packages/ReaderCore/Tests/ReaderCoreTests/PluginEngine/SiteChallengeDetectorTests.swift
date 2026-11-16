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

    func testDoesNotRejectAPageWithTheInjectedChallengePlatformScript() {
        // Cloudflare injects this script into ordinary pages. Treating it as a
        // challenge marker made every protected page fail detection.
        let body = """
            <html><head><title>Example Library</title>
            <script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script>
            </head><body><main id="home-main"></main></body></html>
            """
        XCTAssertFalse(SiteChallengeDetector.isChallenge(status: 200, body: body))
    }

    func testDetectsTheChallengeConfigObject() {
        XCTAssertTrue(
            SiteChallengeDetector.isChallenge(
                status: 200,
                body: "<html><script>window._cf_chl_opt={cvId: '3'}</script></html>"
            )
        )
    }
}
