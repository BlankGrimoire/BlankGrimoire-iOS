// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Native paginated reader for a persisted chapter.
    public struct ReaderView: View {
        private let dependencies: FeaturesDependencies
        @State private var viewModel: ReaderViewModel?
        @State private var challengeRoute: ChallengeRoute?
        @AppStorage("readingDirection") private var readingDirection: ReadingDirection = .vertical
        @Environment(\.dismiss) private var dismiss

        public init(
            manga: MangaEntity,
            chapter: ChapterEntity,
            dependencies: FeaturesDependencies
        ) {
            self.dependencies = dependencies

            if let pageRepository = dependencies.pageRepository,
                let readingProgressRepository = dependencies.readingProgressRepository
            {
                self._viewModel = State(
                    initialValue: ReaderViewModel(
                        manga: manga,
                        chapter: chapter,
                        pageRepository: pageRepository,
                        readingProgressRepository: readingProgressRepository,
                        mangaRepository: dependencies.mangaRepository,
                        chapterPagesProvider: dependencies.chapterPagesProvider
                    )
                )
            } else {
                self._viewModel = State(initialValue: nil)
            }
        }

        public var body: some View {
            if let viewModel {
                readerContent(viewModel)
            } else {
                ContentUnavailableView(
                    "Reader Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The offline reader is not configured on this device.")
                )
            }
        }

        @ViewBuilder
        private func readerContent(_ viewModel: ReaderViewModel) -> some View {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading pages…")
                } else if viewModel.pages.isEmpty {
                    ContentUnavailableView(
                        "No Pages",
                        systemImage: "doc.richtext",
                        description: Text("This chapter has no readable pages.")
                    )
                } else if readingDirection == .vertical {
                    verticalReader(viewModel)
                } else {
                    pagedReader(viewModel)
                }
            }
            .navigationTitle(viewModel.chapter.title ?? "Chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        Task {
                            await viewModel.flushProgress()
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("\(viewModel.pageNumber) / \(viewModel.totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                await viewModel.load()
            }
            .task(id: viewModel.currentPageIndex) {
                await prefetchAdjacentPages(viewModel)
            }
            .onChange(of: viewModel.challengeURL) { _, url in
                guard let url else { return }
                let hosts = Self.allowedHosts(for: viewModel.manga)
                guard !hosts.isEmpty else { return }
                challengeRoute = ChallengeRoute(url: url, allowedHosts: hosts)
            }
            .sheet(item: $challengeRoute) { route in
                ChallengeView(
                    url: route.url,
                    allowedHosts: route.allowedHosts,
                    onFinish: { outcome in
                        challengeRoute = nil
                        guard outcome == .completed else { return }
                        Task { await viewModel.reload() }
                    }
                )
            }
            .alert(
                "Reader Error",
                isPresented: Binding(
                    get: { viewModel.lastError != nil && viewModel.challengeURL == nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.lastError = nil
                        }
                    }
                )
            ) {
                Button("Retry") {
                    Task { await viewModel.reload() }
                }
                Button("OK", role: .cancel) {
                    viewModel.lastError = nil
                }
            } message: {
                Text(viewModel.lastError?.localizedDescription ?? "")
            }
        }

        /// Continuous vertical scrolling for the `vertical` reading mode.
        private func verticalReader(_ viewModel: ReaderViewModel) -> some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, page in
                        CachedAsyncImage(
                            url: page.imageURL,
                            loader: dependencies.imageLoader,
                            headers: page.headers,
                            siteBaseURL: viewModel.manga.siteURL,
                            contentMode: .fit,
                            placeholderIcon: "photo"
                        )
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            guard index != viewModel.currentPageIndex else { return }
                            Task { await viewModel.setPage(index: index) }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.black)
        }

        /// Horizontal paged reading for left-to-right and right-to-left modes.
        private func pagedReader(_ viewModel: ReaderViewModel) -> some View {
            TabView(
                selection: Binding(
                    get: { viewModel.currentPageIndex },
                    set: { index in
                        Task { await viewModel.setPage(index: index) }
                    }
                )
            ) {
                ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, page in
                    CachedAsyncImage(
                        url: page.imageURL,
                        loader: dependencies.imageLoader,
                        headers: page.headers,
                        siteBaseURL: viewModel.manga.siteURL,
                        contentMode: .fit,
                        placeholderIcon: "photo"
                    )
                    .tag(index)
                    .padding(.horizontal)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, readingDirection.layoutDirection)
            .background(Color.black)
        }

        /// Warms the two pages after the current one so a swipe does not wait
        /// for the network. Pages already in flight are deduplicated by the
        /// pipeline, so repeated calls are cheap.
        private func prefetchAdjacentPages(_ viewModel: ReaderViewModel) async {
            guard let loader = dependencies.imageLoader else { return }
            let indices = [viewModel.currentPageIndex + 1, viewModel.currentPageIndex + 2]
                .filter { $0 >= 0 && $0 < viewModel.pages.count }
            guard !indices.isEmpty else { return }

            var headers: [String: [String: String]] = [:]
            let urls = indices.map { index -> String in
                let page = viewModel.pages[index]
                if let pageHeaders = page.headers {
                    headers[page.imageURL] = pageHeaders
                }
                return page.imageURL
            }
            await loader.prefetch(
                urls,
                headers: headers,
                siteBaseURL: viewModel.manga.siteURL
            )
        }

        private static func allowedHosts(for manga: MangaEntity) -> Set<String> {
            guard let siteURL = manga.siteURL, let host = URL(string: siteURL)?.host?.lowercased() else {
                return []
            }
            return [host]
        }
    }

    private struct ChallengeRoute: Identifiable {
        let url: URL
        let allowedHosts: Set<String>

        var id: String { url.absoluteString }
    }

    extension ReadingDirection {
        var layoutDirection: LayoutDirection {
            switch self {
            case .vertical, .horizontalLeftToRight:
                return .leftToRight
            case .horizontalRightToLeft:
                return .rightToLeft
            }
        }
    }
#endif
