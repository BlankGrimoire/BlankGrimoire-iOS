// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Protocol for providing access to theme adapters from various sources.
///
/// Implementations can load themes from local storage, remote repositories,
/// or bundled resources.
public protocol ThemeSource: Sendable {
    /// Returns all available theme adapters from this source.
    func listThemes() async throws -> [ThemeAdapter]

    /// Returns a specific theme adapter by ID.
    func getTheme(id: String) async throws -> ThemeAdapter?

    /// Checks if a theme is available in this source.
    func hasTheme(id: String) async throws -> Bool
}

/// A theme source that loads adapters from the local AdapterStore.
public final class LocalThemeSource: ThemeSource {
    private let adapterStore: any AdapterStore

    public init(adapterStore: any AdapterStore) {
        self.adapterStore = adapterStore
    }

    public func listThemes() async throws -> [ThemeAdapter] {
        let bundles = try await adapterStore.listInstalledAdapters()
        return bundles.map { $0.themeAdapter }
    }

    public func getTheme(id: String) async throws -> ThemeAdapter? {
        let bundles = try await adapterStore.listInstalledAdapters()
        return bundles.first { $0.themeAdapter.id == id }?.themeAdapter
    }

    public func hasTheme(id: String) async throws -> Bool {
        let bundles = try await adapterStore.listInstalledAdapters()
        return bundles.contains { $0.themeAdapter.id == id }
    }
}

/// A theme source that fetches adapters from a remote repository index.
public final class RemoteThemeSource: ThemeSource {
    private let repositoryURL: String
    private let requestHandler: PluginRequestHandler

    public init(repositoryURL: String, requestHandler: PluginRequestHandler) {
        self.repositoryURL = repositoryURL
        self.requestHandler = requestHandler
    }

    public func listThemes() async throws -> [ThemeAdapter] {
        let index = try await fetchIndex()
        return index.extensions.map { entry in
            // Create a minimal ThemeAdapter from the index entry
            // The full adapter will be downloaded on demand
            ThemeAdapter(
                id: entry.id,
                name: entry.name,
                version: entry.version,
                detectionSignature: ThemeSignature(minScore: 1),
                selectors: ThemeSelectors(
                    search: .init(path: "", item: "", title: "", link: ""),
                    details: .init(
                        title: "", cover: nil, synopsis: nil, authors: nil, artists: nil, altTitles: nil, tags: nil,
                        status: nil, contentRating: nil),
                    chapters: .init(item: "", link: "", title: nil, date: nil, order: "desc"),
                    pages: .init(strategies: []),
                    attribution: nil
                )
            )
        }
    }

    public func getTheme(id: String) async throws -> ThemeAdapter? {
        let index = try await fetchIndex()
        guard let entry = index.extensions.first(where: { $0.id == id }) else { return nil }

        return ThemeAdapter(
            id: entry.id,
            name: entry.name,
            version: entry.version,
            detectionSignature: ThemeSignature(minScore: 1),
            selectors: ThemeSelectors(
                search: .init(path: "", item: "", title: "", link: ""),
                details: .init(
                    title: "", cover: nil, synopsis: nil, authors: nil, artists: nil, altTitles: nil, tags: nil,
                    status: nil, contentRating: nil),
                chapters: .init(item: "", link: "", title: nil, date: nil, order: "desc"),
                pages: .init(strategies: []),
                attribution: nil
            )
        )
    }

    public func hasTheme(id: String) async throws -> Bool {
        let index = try await fetchIndex()
        return index.extensions.contains { $0.id == id }
    }

    private func fetchIndex() async throws -> RepositoryIndex {
        let request = HttpRequest(url: repositoryURL, method: "GET")
        let response = try await requestHandler.perform(request)

        guard response.status >= 200 && response.status < 300 else {
            throw AdapterStoreError.networkError("HTTP \(response.status)")
        }

        let data = Data(response.body.utf8)
        return try JSONDecoder().decode(RepositoryIndex.self, from: data)
    }
}

/// A composite theme source that checks multiple sources in order.
public final class CompositeThemeSource: ThemeSource {
    private let sources: [ThemeSource]

    public init(sources: [ThemeSource]) {
        self.sources = sources
    }

    public func listThemes() async throws -> [ThemeAdapter] {
        var allThemes: [ThemeAdapter] = []
        for source in sources {
            let themes = try await source.listThemes()
            allThemes.append(contentsOf: themes)
        }
        // Deduplicate by ID, keeping first occurrence
        var seen = Set<String>()
        return allThemes.filter { seen.insert($0.id).inserted }
    }

    public func getTheme(id: String) async throws -> ThemeAdapter? {
        for source in sources {
            if let theme = try await source.getTheme(id: id) {
                return theme
            }
        }
        return nil
    }

    public func hasTheme(id: String) async throws -> Bool {
        for source in sources {
            if try await source.hasTheme(id: id) {
                return true
            }
        }
        return false
    }
}

/// Errors for theme source operations.
public enum ThemeSourceError: Error, LocalizedError, Sendable, Equatable {
    case repositoryUnavailable(String)
    case invalidIndex(String)
    case themeNotFound(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .repositoryUnavailable(let url):
            return "Theme repository unavailable: \(url)"
        case .invalidIndex(let msg):
            return "Invalid repository index: \(msg)"
        case .themeNotFound(let id):
            return "Theme not found: \(id)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}
