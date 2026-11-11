// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Normalisation helpers for user-entered site URLs.
public enum SiteURL {
    /// Returns a URL with an explicit, secure `https` scheme and a valid host.
    ///
    /// Plain `http` is rejected: site credentials and page content must never
    /// travel unencrypted.
    public static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if let separator = trimmed.range(of: "://") {
            let scheme = trimmed[..<separator.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard
            var components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            scheme == "https",
            let host = components.host?.lowercased(),
            !host.isEmpty
        else {
            return nil
        }

        // Normalise the host so `Example.ORG` and `example.org` produce the
        // same base URL and allowlist entry.
        components.scheme = "https"
        components.host = host
        return components.url
    }

    /// Returns the site root, preserving a meaningful path prefix.
    ///
    /// Sites served from a subdirectory (for example a catalog under
    /// `/library`) keep that prefix; only query, fragment and credentials are
    /// removed and trailing slashes are trimmed.
    public static func siteBaseURLString(from raw: String) -> String? {
        guard
            let url = normalizedURL(from: raw),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path == "/" ? "" : path

        guard var value = components.url?.absoluteString else { return nil }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
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
