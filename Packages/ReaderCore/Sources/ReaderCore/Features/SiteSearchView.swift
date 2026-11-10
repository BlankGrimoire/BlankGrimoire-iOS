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
        public var sites: [SiteProfile] = []
        public private(set) var results: [SiteSearchResult] = []
        public private(set) var failures: [SiteSearchFailure] = []
        public private(set) var isSearching = false
        public private(set) var hasSearched = false
        public private(set) var importingIDs: Set<String> = []
        public private(set) var importedIDs: Set<String> = []
        public var lastError: Error?

        private let siteProfileRepository: any SiteProfileRepository
        private let catalogService: (any SiteCatalogProviding)?

        public init(
            siteProfileRepository: any SiteProfileRepository,
            catalogService: (any SiteCatalogProviding)?
        ) {
            self.siteProfileRepository = siteProfileRepository
            self.catalogService = catalogService
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

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results = []
                failures = []
                hasSearched = false
                return
            }

            await loadSites()

            let targets = targetSites
            guard !targets.isEmpty else {
                results = []
                failures = []
                hasSearched = true
                return
            }

            isSearching = true
            lastError = nil
            defer { isSearching = false }

            let outcome = await catalogService.search(query: trimmed, in: targets)
            results = outcome.results
            failures = outcome.failures
            hasSearched = true
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
            query = ""
            results = []
            failures = []
            hasSearched = false
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
                    catalogService: dependencies.catalogService
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
                } else if viewModel.searchableSites.isEmpty {
                    ContentUnavailableView {
                        Label("No Sites Yet", systemImage: "globe")
                    } description: {
                        Text("Add a site and install its adapter before searching.")
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
                    onComplete: {
                        challengeRoute = nil
                        viewModel.lastError = nil
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

                if !viewModel.results.isEmpty {
                    Section("Results") {
                        ForEach(viewModel.results) { result in
                            resultRow(result)
                        }
                    }
                }

                if viewModel.hasSearched && viewModel.results.isEmpty && !viewModel.isSearching {
                    Section {
                        ContentUnavailableView.search(text: viewModel.query)
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
