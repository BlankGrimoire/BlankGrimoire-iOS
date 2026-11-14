// SPDX-License-Identifier: MPL-2.0

import Foundation

/// The page and site data required to invoke an adapter method.
public struct PluginPageContext: Sendable, Equatable {
    /// HTML of the page currently being inspected.
    public let html: String
    /// Absolute site base URL used to resolve relative links and images.
    public let baseURL: String
    /// Display name of the user-selected site.
    public let siteName: String
    /// User selector overrides for this site.
    public let overrides: ThemeSelectorsOverrides

    public init(
        html: String,
        baseURL: String,
        siteName: String,
        overrides: ThemeSelectorsOverrides = ThemeSelectorsOverrides()
    ) {
        self.html = html
        self.baseURL = baseURL
        self.siteName = siteName
        self.overrides = overrides
    }
}
