// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Detects verification pages that can be returned with a successful HTTP
/// status, such as a browser challenge rendered instead of the requested page.
enum SiteChallengeDetector {
    static func isChallenge(status: Int, body: String) -> Bool {
        if status == 403 || status == 503 {
            return true
        }

        let normalized = body.lowercased()
        // `challenge-platform` is deliberately absent: Cloudflare injects
        // `/cdn-cgi/challenge-platform/...` into pages that are not challenges,
        // so matching it made every protected page look blocked.
        let markers = [
            "<title>just a moment",
            "cf-chl-",
            "cf_chl_opt",
            "challenge-error-text",
            "verify you are human",
            "enable javascript and cookies",
            "sorry, you have been blocked",
        ]
        return markers.contains { normalized.contains($0) }
    }
}
