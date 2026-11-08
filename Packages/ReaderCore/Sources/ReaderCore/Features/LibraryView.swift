// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Main library view showing the user's collection
    public struct LibraryView: View {
        let dependencies: FeaturesDependencies
        @State private var viewModel: LibraryViewModel
        @AppStorage("autoUpdate") private var autoUpdate: Bool = true

        public init(dependencies: FeaturesDependencies) {
            self.dependencies = dependencies
            self._viewModel = State(
                initialValue: LibraryViewModel(mangaRepository: dependencies.mangaRepository)
            )
        }

        public var body: some View {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading library...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredManga.isEmpty {
                    emptyStateView
                } else {
                    mangaGrid
                }
            }
            .navigationTitle("Library")
            .searchable(text: $viewModel.searchText, prompt: "Search your library...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort", selection: $viewModel.sortOption) {
                            ForEach(LibrarySortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        Divider()
                        Picker("Filter", selection: $viewModel.filterOption) {
                            ForEach(LibraryFilterOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                await viewModel.loadManga()
            }
            .onAppear {
                if autoUpdate || viewModel.manga.isEmpty {
                    Task { await viewModel.loadManga() }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.lastError != nil },
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

        private var emptyStateView: some View {
            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "book.closed")
                    .font(.system(size: 64))
                    .foregroundStyle(.tertiary)

                Text(viewModel.searchText.isEmpty ? "Your library is empty" : "No results found")
                    .font(Typography.title2)
                    .foregroundStyle(.secondary)

                if viewModel.searchText.isEmpty {
                    Text("Add series from your sites to start building your library")
                        .font(Typography.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var mangaGrid: some View {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: DesignTokens.Spacing.md) {
                    ForEach(viewModel.filteredManga) { manga in
                        NavigationLink {
                            MangaDetailView(manga: manga, dependencies: dependencies)
                        } label: {
                            MangaCard(manga: manga, imageLoader: dependencies.imageLoader)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }

        private var gridColumns: [GridItem] {
            [
                GridItem(.adaptive(minimum: 140), spacing: DesignTokens.Spacing.md)
            ]
        }
    }

    /// Individual manga card in the library grid
    private struct MangaCard: View {
        let manga: MangaEntity
        let imageLoader: (any ImageLoading)?

        var body: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ZStack(alignment: .bottomTrailing) {
                    MangaCoverImage(url: manga.coverURL, loader: imageLoader)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))

                    if manga.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(DesignTokens.Spacing.xs)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(DesignTokens.Spacing.xs)
                    }

                    if manga.readingProgress > 0 {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("\(Int(manga.readingProgress * 100))%")
                                    .font(Typography.caption1.weight(.medium))
                                    .padding(.horizontal, DesignTokens.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(.black.opacity(0.7), in: Capsule())
                                    .foregroundStyle(.white)
                                    .padding(DesignTokens.Spacing.xs)
                            }
                        }
                    }
                }

                Text(manga.title)
                    .font(Typography.footnote.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let siteName = manga.siteName {
                    Text(siteName)
                        .font(Typography.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let lastReadAt = manga.lastReadAt {
                    Text("Read \(lastReadAt, style: .offset)")
                        .font(Typography.caption1)
                        .foregroundStyle(.tertiary)
                }
            }
            .card()
        }
    }

    #if DEBUG
        #Preview {
            NavigationStack {
                LibraryView(dependencies: .preview)
            }
        }
    #endif
#endif
