// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Native paginated reader for a persisted chapter.
    public struct ReaderView: View {
        private let dependencies: FeaturesDependencies
        @State private var viewModel: ReaderViewModel
        @Environment(\.dismiss) private var dismiss

        public init(
            manga: MangaEntity,
            chapter: ChapterEntity,
            dependencies: FeaturesDependencies
        ) {
            self.dependencies = dependencies
            guard
                let pageRepository = dependencies.pageRepository,
                let readingProgressRepository = dependencies.readingProgressRepository
            else {
                fatalError("ReaderView requires page and reading-progress repositories")
            }

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
        }

        public var body: some View {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading pages…")
                } else if viewModel.pages.isEmpty {
                    ContentUnavailableView(
                        "No Pages",
                        systemImage: "doc.richtext",
                        description: Text("This chapter has no readable pages.")
                    )
                } else {
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
                                contentMode: .fit,
                                placeholderIcon: "photo"
                            )
                            .tag(index)
                            .padding(.horizontal)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .background(Color.black)
                }
            }
            .navigationTitle(viewModel.chapter.title ?? "Chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        Task {
                            await viewModel.saveProgress()
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
            .alert(
                "Reader Error",
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
    }
#endif
