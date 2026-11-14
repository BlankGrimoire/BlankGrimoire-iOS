// SPDX-License-Identifier: MPL-2.0

import Foundation

/// One user agent for every network surface.
///
/// Verification cookies (for example Cloudflare's `cf_clearance`) are bound to
/// the user agent that solved the challenge. Native requests, the hidden
/// hybrid web view and the visible verification browser must therefore present
/// the same value.
public enum UserAgent {
    public static let `default` =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
