// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Canonicalization for user-entered adapter repository index URLs.
enum RepositoryURL {
    static let indexFileName = "index.json"

    /// Returns an HTTPS repository index URL.
    ///
    /// - Adds `https://` when the user omits the scheme.
    /// - Appends `index.json` only when the path is empty or ends with `/`,
    ///   so an explicit custom endpoint is never rewritten.
    static func normalizedIndexURL(from raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if let separator = value.range(of: "://") {
            let scheme = value[..<separator.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else {
                return nil
            }
        } else {
            value = "https://\(value)"
        }

        guard
            var components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            let host = components.host?.lowercased(),
            !host.isEmpty
        else {
            return nil
        }

        components.scheme = "https"
        components.host = host
        components.fragment = nil
        components.user = nil
        components.password = nil

        var path = components.path
        if path.isEmpty || path == "/" {
            path = "/\(indexFileName)"
        } else if path.hasSuffix("/") {
            path += indexFileName
        }
        components.path = path

        return components.url
    }
}
