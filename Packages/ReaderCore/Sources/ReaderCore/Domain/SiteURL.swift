// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Normalisation helpers for user-entered site URLs.
public enum SiteURL {
    /// Returns a URL with an explicit `http`/`https` scheme and a valid host.
    public static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard
            let url = URL(string: candidate),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty
        else {
            return nil
        }

        return url
    }

    /// Returns a canonical scheme + host base URL without path, query or fragment.
    public static func baseURLString(from raw: String) -> String? {
        guard
            let url = normalizedURL(from: raw),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        guard var value = components.url?.absoluteString else { return nil }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    /// Returns the lowercased host of a user-entered URL.
    public static func host(from raw: String) -> String? {
        normalizedURL(from: raw)?.host?.lowercased()
    }
}
