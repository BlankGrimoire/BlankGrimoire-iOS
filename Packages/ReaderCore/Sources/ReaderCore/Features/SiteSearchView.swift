// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

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
        @State private var selectedResult: SiteSearchResult?

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
                text: Binding(
                    get: { viewModel.query },
                    set: { newValue in
                        viewModel.query = newValue
                        // A title query and a genre filter are mutually
                        // exclusive: typing replaces the selected genre.
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.selectedGenre = nil
                        }
                    }
                ),
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
                        (viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && viewModel.selectedGenre == nil)
                            || viewModel.isSearching
                    )
                }
            }
            .task {
                await viewModel.loadSites()
            }
            .onChange(of: viewModel.selectedSiteIDs) {
                Task {
                    await viewModel.reloadGenres()
                    guard viewModel.hasSearched else { return }
                    await viewModel.search()
                }
            }
            .onChange(of: viewModel.selectedGenre) { _, newGenre in
                // Only a genre selection starts a search automatically;
                // clearing the genre while typing must not fire one.
                guard viewModel.hasSearched, newGenre != nil else { return }
                Task { await viewModel.search() }
            }
            .onChange(of: viewModel.challengeURL) { _, url in
                guard let url else { return }
                let hosts = challengeHosts(for: url)
                guard !hosts.isEmpty else { return }
                challengeRoute = ChallengeRoute(url: url, allowedHosts: hosts)
            }
            .navigationDestination(item: $selectedResult) { result in
                SearchResultDetailView(
                    result: result,
                    alreadyImported: viewModel.importedIDs.contains(result.id),
                    dependencies: dependencies
                )
            }
            .sheet(item: $challengeRoute) { route in
                ChallengeView(
                    url: route.url,
                    allowedHosts: route.allowedHosts,
                    onFinish: { outcome in
                        challengeRoute = nil
                        guard outcome == .completed else { return }
                        viewModel.lastError = nil
                        Task { await viewModel.search() }
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
                    ForEach(viewModel.searchableSites) { site in
                        Button {
                            viewModel.toggleSite(site)
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.sm) {
                                Image(
                                    systemName: viewModel.isSiteSelected(site)
                                        ? "checkmark.square.fill"
                                        : "square"
                                )
                                .foregroundStyle(
                                    viewModel.isSiteSelected(site)
                                        ? AppColor.primary
                                        : AppColor.onSurfaceVariant
                                )

                                Text(site.name)

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(site.name)
                        .accessibilityValue(viewModel.isSiteSelected(site) ? "Included" : "Excluded")
                    }
                } header: {
                    HStack {
                        Text("Sites")
                        Spacer()
                        Button(viewModel.areAllSitesSelected ? "Deselect all" : "Select all") {
                            viewModel.setAllSitesSelected(!viewModel.areAllSitesSelected)
                        }
                        .font(Typography.caption1)
                        .textCase(nil)
                    }
                } footer: {
                    if viewModel.targetSites.isEmpty {
                        Text("Select at least one site to search.")
                            .font(Typography.caption1)
                    }
                }

                Section {
                    Picker(
                        "Genere",
                        selection: Binding(
                            get: { viewModel.selectedGenre },
                            set: { newValue in
                                viewModel.selectedGenre = newValue
                                // Selecting a genre replaces the title query.
                                if newValue != nil {
                                    viewModel.query = ""
                                }
                            }
                        )
                    ) {
                        Text("Tutti i generi").tag(String?.none)
                        ForEach(viewModel.unifiedGenres) { genre in
                            HStack {
                                Text(genre.displayName)
                                if genre.siteFilters.count > 1 {
                                    Text("(\(genre.siteFilters.count) siti)")
                                        .foregroundStyle(.secondary)
                                }
                            }.tag(Optional(genre.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Label(
                        "The genre filter replaces the title search: use one or the other.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

        private func challengeHosts(for url: URL) -> Set<String> {
            guard let host = url.host?.lowercased() else { return [] }
            let candidates = viewModel.sites.compactMap {
                URL(string: $0.baseURL)?.host?.lowercased()
            }
            return Set(candidates.filter { host == $0 || host.hasSuffix("." + $0) })
        }

        private func resultRow(_ result: SiteSearchResult) -> some View {
            HStack(spacing: DesignTokens.Spacing.md) {
                Button {
                    selectedResult = result
                } label: {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        MangaCoverImage(
                            url: result.coverURL,
                            loader: dependencies.imageLoader,
                            siteBaseURL: result.siteURL
                        )
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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
