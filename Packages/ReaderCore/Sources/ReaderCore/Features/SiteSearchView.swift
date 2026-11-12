// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Cross-site search and import flow.
    ///
    /// The user types a title (or a filter) once and the app queries every
    /// enabled site profile that is stored locally. Results are grouped by
    /// site, and each row can be imported into the library together with its
    /// chapter list.
    @MainActor
    @Observable
    public final class SiteSearchViewModel {
        public var query: String = ""
        public var selectedSiteID: String?
        public var selectedGenres: Set<String> = []
        public var sites: [SiteProfile] = []
        public private(set) var results: [SiteSearchResult] = []
        public private(set) var failures: [SiteSearchFailure] = []
        public private(set) var isSearching = false
        public private(set) var isLoadingMore = false
        public private(set) var hasSearched = false
        /// Whether the last site page announced another result page.
        public private(set) var hasMoreResults = false
        public private(set) var importingIDs: Set<String> = []
        public private(set) var importedIDs: Set<String> = []
        public var lastError: Error?

        private let siteProfileRepository: any SiteProfileRepository
        private let catalogService: (any SiteCatalogProviding)?
        private let mangaRepository: (any MangaRepository)?
        /// Incremented on every search so stale results from a superseded
        /// request cannot overwrite the latest one.
        private var searchGeneration = 0
        /// Cursors for the next page, keyed by site profile id.
        private var nextPageURLs: [String: String] = [:]

        public init(
            siteProfileRepository: any SiteProfileRepository,
            catalogService: (any SiteCatalogProviding)?,
            mangaRepository: (any MangaRepository)? = nil
        ) {
            self.siteProfileRepository = siteProfileRepository
            self.catalogService = catalogService
            self.mangaRepository = mangaRepository
        }

        /// True when the composition root supplied a catalog service.
        public var isAvailable: Bool {
            catalogService != nil
        }

        /// URL the visible verification browser must open, when the last
        /// operation was stopped by a site challenge.
        public var challengeURL: URL? {
            guard let error = lastError as? SiteBrowsingError else { return nil }
            if case .challengeRequired(let url) = error {
                return url
            }
            return nil
        }

        /// Sites that can receive the next search.
        public var searchableSites: [SiteProfile] {
            sites.filter(\.isEnabled)
        }

        public var targetSites: [SiteProfile] {
            guard let selectedSiteID else {
                return searchableSites
            }
            return searchableSites.filter { $0.id == selectedSiteID }
        }

        public func loadSites() async {
            do {
                sites = try await siteProfileRepository.fetchAll()
                if let selectedSiteID, !sites.contains(where: { $0.id == selectedSiteID }) {
                    self.selectedSiteID = nil
                }
            } catch {
                lastError = error
            }
        }

        public func search() async {
            guard let catalogService else {
                lastError = SiteBrowsingError.catalogUnavailable
                return
            }

            let searchQuery = SearchQuery(
                text: query.trimmingCharacters(in: .whitespacesAndNewlines), page: 1, genres: Array(selectedGenres))
            guard !searchQuery.text!.isEmpty || !searchQuery.genres!.isEmpty else {
                results = []
                failures = []
                hasSearched = false
                hasMoreResults = false
                nextPageURLs = [:]
                return
            }

            await loadSites()

            let targets = targetSites
            guard !targets.isEmpty else {
                results = []
                failures = []
                hasSearched = true
                hasMoreResults = false
                nextPageURLs = [:]
                return
            }

            searchGeneration += 1
            let generation = searchGeneration
            isSearching = true
            lastError = nil
            defer {
                if generation == searchGeneration {
                    isSearching = false
                }
            }

            let outcome = await catalogService.search(searchQuery, in: targets)
            guard generation == searchGeneration, !Task.isCancelled else { return }
            results = outcome.results
            failures = outcome.failures
            nextPageURLs = outcome.nextPageURLs
            hasMoreResults = outcome.hasMore
            hasSearched = true
            await refreshImportedIDs()
        }

        /// Loads the next result page and appends it to the current list.
        ///
        /// Each site exposes its own "next" link, so the catalog returns the
        /// new cursor alongside the new results.
        public func loadMore() async {
            guard let catalogService, !isSearching, !isLoadingMore, hasMoreResults,
                !nextPageURLs.isEmpty
            else {
                return
            }

            let searchQuery = SearchQuery(
                text: query.trimmingCharacters(in: .whitespacesAndNewlines), page: 1, genres: Array(selectedGenres))
            guard !searchQuery.text!.isEmpty || !searchQuery.genres!.isEmpty else { return }

            let outcome = SiteSearchOutcome(
                results: results,
                failures: failures,
                nextPageURLs: nextPageURLs
            )
            let generation = searchGeneration
            isLoadingMore = true
            lastError = nil
            defer {
                if generation == searchGeneration {
                    isLoadingMore = false
                }
            }

            let next = await catalogService.searchNextPage(
                query: searchQuery,
                in: targetSites,
                continuingFrom: outcome
            )
            guard generation == searchGeneration, !Task.isCancelled else { return }

            var seen = Set(results.map(\.id))
            results.append(contentsOf: next.results.filter { seen.insert($0.id).inserted })
            var failedSites = Set(failures.map(\.siteProfileID))
            failures.append(contentsOf: next.failures.filter { failedSites.insert($0.siteProfileID).inserted })
            nextPageURLs = next.nextPageURLs
            hasMoreResults = next.hasMore
            await refreshImportedIDs()
        }

        /// Rebuilds the "already in library" state from persisted data so it
        /// survives a new view model or an app relaunch.
        private func refreshImportedIDs() async {
            guard let mangaRepository, !results.isEmpty else { return }
            do {
                let imported = try await mangaRepository.fetchByIds(results.map(\.id))
                importedIDs = Set(imported.map(\.id))
            } catch {
                lastError = error
            }
        }

        public func importResult(_ result: SiteSearchResult) async {
            guard let catalogService else {
                lastError = SiteBrowsingError.catalogUnavailable
                return
            }
            guard !importingIDs.contains(result.id) else { return }

            importingIDs.insert(result.id)
            lastError = nil
            defer { importingIDs.remove(result.id) }

            do {
                _ = try await catalogService.importManga(result)
                importedIDs.insert(result.id)
            } catch {
                lastError = error
            }
        }

        public func reset() {
            searchGeneration += 1
            query = ""
            results = []
            failures = []
            nextPageURLs = [:]
            hasMoreResults = false
            hasSearched = false
            isSearching = false
            isLoadingMore = false
        }
    }

    private struct ChallengeRoute: Identifiable {
        let url: URL
        let allowedHosts: Set<String>

        var id: String { url.absoluteString }
    }

    /// General search across every saved site.
    public struct SiteSearchView: View {
        private let dependencies: FeaturesDependencies
        @State private var viewModel: SiteSearchViewModel
        @State private var challengeRoute: ChallengeRoute?

        public init(dependencies: FeaturesDependencies) {
            self.dependencies = dependencies
            self._viewModel = State(
                initialValue: SiteSearchViewModel(
                    siteProfileRepository: dependencies.siteProfileRepository,
                    catalogService: dependencies.catalogService,
                    mangaRepository: dependencies.mangaRepository
                )
            )
        }

        public var body: some View {
            Group {
                if !viewModel.isAvailable {
                    ContentUnavailableView(
                        "Browsing Unavailable",
                        systemImage: "magnifyingglass",
                        description: Text("Site browsing is not configured for this build.")
                    )
                } else if viewModel.sites.isEmpty {
                    ContentUnavailableView {
                        Label("No Sites Yet", systemImage: "globe")
                    } description: {
                        Text("Add a site and install its adapter before searching.")
                    }
                } else if viewModel.searchableSites.isEmpty {
                    ContentUnavailableView {
                        Label("All Sites Are Disabled", systemImage: "pause.circle")
                    } description: {
                        Text("Enable at least one site in Settings to search it.")
                    }
                } else {
                    resultsList
                }
            }
            .navigationTitle("Browse")
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search all sites"
            )
            .onSubmit(of: .search) {
                Task { await viewModel.search() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.search() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(
                        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.isSearching
                    )
                }
            }
            .task {
                await viewModel.loadSites()
            }
            .onChange(of: viewModel.selectedSiteID) {
                guard viewModel.hasSearched else { return }
                Task { await viewModel.search() }
            }
            .onChange(of: viewModel.challengeURL) { _, url in
                guard let url else { return }
                let hosts = Set(
                    viewModel.sites.compactMap { URL(string: $0.baseURL)?.host?.lowercased() }
                ).filter { host in
                    url.host?.lowercased() == host
                        || url.host?.lowercased().hasSuffix("." + host) == true
                }
                guard !hosts.isEmpty else { return }
                challengeRoute = ChallengeRoute(url: url, allowedHosts: Set(hosts))
            }
            .sheet(item: $challengeRoute) { route in
                ChallengeView(
                    url: route.url,
                    allowedHosts: route.allowedHosts,
                    onFinish: { outcome in
                        challengeRoute = nil
                        if outcome == .completed {
                            viewModel.lastError = nil
                        }
                    }
                )
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.lastError != nil && viewModel.challengeURL == nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.lastError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.lastError = nil
                }
            } message: {
                Text(viewModel.lastError?.localizedDescription ?? "")
            }
        }

        private static let commonGenres: Set<String> = [
            "action", "adventure", "comedy", "drama", "fantasy", "horror",
            "isekai", "romance", "sci-fi", "slice-of-life", "sports",
            "supernatural", "thriller", "historical", "psychological",
            "mystery", "ecchi", "harem", "shounen", "shoujo", "seinen", "josei",
        ]

        private var resultsList: some View {
            List {
                if viewModel.isSearching {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Searching \(viewModel.targetSites.count) site(s)…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("Search in", selection: $viewModel.selectedSiteID) {
                        Text("All sites").tag(String?.none)
                        ForEach(viewModel.searchableSites) { site in
                            Text(site.name).tag(Optional(site.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Picker("Genres", selection: $viewModel.selectedGenres) {
                        Text("All Genres").tag(Set<String>())
                        ForEach(Array(Self.commonGenres).sorted(), id: \.self) { genre in
                            Text(genre.capitalized).tag(Set([genre]))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !viewModel.results.isEmpty {
                    Section("Results") {
                        ForEach(viewModel.results) { result in
                            resultRow(result)
                        }

                        if viewModel.hasMoreResults {
                            Button {
                                Task { await viewModel.loadMore() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if viewModel.isLoadingMore {
                                        ProgressView()
                                    } else {
                                        Text("Load More")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(viewModel.isLoadingMore)
                        }
                    }
                }

                if viewModel.hasSearched && viewModel.results.isEmpty && !viewModel.isSearching {
                    Section {
                        if viewModel.failures.isEmpty {
                            ContentUnavailableView.search(text: viewModel.query)
                        } else {
                            ContentUnavailableView {
                                Label("No Results", systemImage: "exclamationmark.magnifyingglass")
                            } description: {
                                Text(
                                    "No site returned results. Check the issues below and try again."
                                )
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if !viewModel.failures.isEmpty {
                    Section("Sites with issues") {
                        ForEach(viewModel.failures) { failure in
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                                Text(failure.siteName)
                                    .font(Typography.body.weight(.medium))
                                Text(failure.message)
                                    .font(Typography.caption1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.loadSites()
            }
        }

        private func resultRow(_ result: SiteSearchResult) -> some View {
            HStack(spacing: DesignTokens.Spacing.md) {
                MangaCoverImage(url: result.coverURL, loader: dependencies.imageLoader)
                    .frame(width: 56, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(result.title)
                        .font(Typography.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(result.siteName)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: DesignTokens.Spacing.sm)

                importButton(for: result)
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
        }

        @ViewBuilder
        private func importButton(for result: SiteSearchResult) -> some View {
            if viewModel.importingIDs.contains(result.id) {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.importedIDs.contains(result.id) {
                Label("In Library", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await viewModel.importResult(result) }
                } label: {
                    Label("Import", systemImage: "plus.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    #if DEBUG
        #Preview {
            NavigationStack {
                SiteSearchView(dependencies: .preview)
            }
        }
    #endif
#endif
