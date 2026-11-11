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
        let markers = [
            "<title>just a moment",
            "cf-chl-",
            "challenge-platform",
            "verify you are human",
            "enable javascript and cookies",
            "sorry, you have been blocked",
            "hcaptcha",
            "turnstile",
        ]
        return markers.contains { normalized.contains($0) }
    }
}
