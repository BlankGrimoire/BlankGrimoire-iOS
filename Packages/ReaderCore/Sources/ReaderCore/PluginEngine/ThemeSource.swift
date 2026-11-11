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
///
/// The index is cached in memory and revalidated with its ETag. Adapters listed
/// here are summaries; the full bundle is downloaded and verified by
/// `AdapterStore` before installation.
public actor RemoteThemeSource: ThemeSource {
    private struct CachedIndex {
        let index: RepositoryIndex
        let etag: String?
        let fetchedAt: Date
    }

    private let repositoryURL: String
    private let requestHandler: PluginRequestHandler
    private let cacheLifetime: TimeInterval
    private var cachedIndex: CachedIndex?

    public init(
        repositoryURL: String,
        requestHandler: PluginRequestHandler,
        cacheLifetime: TimeInterval = 5 * 60
    ) {
        self.repositoryURL = repositoryURL
        self.requestHandler = requestHandler
        self.cacheLifetime = max(0, cacheLifetime)
    }

    /// Drops the cached index, for example after an adapter install changes the
    /// local version of a theme.
    public func invalidateCache() {
        cachedIndex = nil
    }

    public func listThemes() async throws -> [ThemeAdapter] {
        let index = try await fetchIndex()
        return index.extensions.map(makeSummaryAdapter)
    }

    public func getTheme(id: String) async throws -> ThemeAdapter? {
        let index = try await fetchIndex()
        guard let entry = index.extensions.first(where: { $0.id == id }) else {
            return nil
        }
        return makeSummaryAdapter(entry)
    }

    public func hasTheme(id: String) async throws -> Bool {
        let index = try await fetchIndex()
        return index.extensions.contains { $0.id == id }
    }

    private func makeSummaryAdapter(_ entry: ExtensionEntry) -> ThemeAdapter {
        // The index only carries identity and version. Detection and selectors
        // become available after the bundle is downloaded and verified.
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

    private func fetchIndex() async throws -> RepositoryIndex {
        if let cachedIndex, Date().timeIntervalSince(cachedIndex.fetchedAt) < cacheLifetime {
            return cachedIndex.index
        }

        var headers: [String: String] = [:]
        if let etag = cachedIndex?.etag {
            headers["If-None-Match"] = etag
        }

        let request = HttpRequest(
            url: repositoryURL,
            method: "GET",
            headers: headers.isEmpty ? nil : headers
        )
        let response = try await requestHandler.perform(request)

        if response.status == 304, let cachedIndex {
            self.cachedIndex = CachedIndex(
                index: cachedIndex.index,
                etag: cachedIndex.etag,
                fetchedAt: Date()
            )
            return cachedIndex.index
        }

        guard response.status >= 200 && response.status < 300 else {
            throw ThemeSourceError.repositoryUnavailable(repositoryURL)
        }

        let index: RepositoryIndex
        do {
            index = try JSONDecoder().decode(
                RepositoryIndex.self,
                from: Data(response.body.utf8)
            )
        } catch {
            throw ThemeSourceError.invalidIndex(error.localizedDescription)
        }

        cachedIndex = CachedIndex(
            index: index,
            etag: response.headers.first {
                $0.key.caseInsensitiveCompare("ETag") == .orderedSame
            }?.value,
            fetchedAt: Date()
        )
        return index
    }
}

/// A composite theme source that checks multiple sources in order.
///
/// A failing source never hides the successful ones. Duplicate ids keep the
/// highest semantic version, so an installed adapter does not mask a newer
/// remote release.
public final class CompositeThemeSource: ThemeSource {
    private let sources: [ThemeSource]

    public init(sources: [ThemeSource]) {
        self.sources = sources
    }

    public func listThemes() async throws -> [ThemeAdapter] {
        var bestByID: [String: ThemeAdapter] = [:]
        var firstError: Error?
        var anySourceSucceeded = false

        for source in sources {
            do {
                let themes = try await source.listThemes()
                anySourceSucceeded = true
                for theme in themes {
                    if let existing = bestByID[theme.id] {
                        if AdapterVersion(theme.version) > AdapterVersion(existing.version) {
                            bestByID[theme.id] = theme
                        }
                    } else {
                        bestByID[theme.id] = theme
                    }
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if !anySourceSucceeded, let firstError {
            throw firstError
        }

        return bestByID.values.sorted { $0.id < $1.id }
    }

    public func getTheme(id: String) async throws -> ThemeAdapter? {
        let themes = try await listThemes()
        return themes.first { $0.id == id }
    }

    public func hasTheme(id: String) async throws -> Bool {
        try await getTheme(id: id) != nil
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
