// SPDX-License-Identifier: MPL-2.0

import Foundation
import ReaderCore

/// Static app configuration read from the bundle.
///
/// The official theme repository is a default, not a hardcoded assumption: it
/// can be overridden in `Info.plist` (`BlankGrimoireThemesRepositoryURL`) or in
/// a build configuration without touching the composition root.
enum AppConfiguration {
    static let defaultThemesRepositoryURL =
        "https://blankgrimoire.github.io/BlankGrimoire-themes/index.json"

    static func themesRepositoryURL(in bundle: Bundle = .main) -> String {
        validatedThemesRepositoryURL(
            bundle.object(forInfoDictionaryKey: "BlankGrimoireThemesRepositoryURL") as? String
        )
    }

    /// Returns the configured URL when it is a usable HTTPS URL, otherwise the
    /// official default.
    static func validatedThemesRepositoryURL(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            let url = URL(string: value),
            url.scheme?.lowercased() == "https",
            let host = url.host,
            !host.isEmpty
        else {
            return defaultThemesRepositoryURL
        }
        return value
    }

    /// Builds a network policy scoped to the configured repository host.
    static func themesRepositoryPolicy(for url: String) -> SiteNetworkPolicy {
        guard let parsed = URL(string: url),
            let host = parsed.host,
            !host.isEmpty
        else {
            return themesRepositoryPolicy(for: defaultThemesRepositoryURL)
        }

        let scheme = parsed.scheme?.lowercased() ?? "https"
        return SiteNetworkPolicy(
            baseURL: "\(scheme)://\(host)",
            allowedHosts: [host]
        )
    }
}
