// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import Foundation
    import SwiftUI

    /// Native paginated reader for a persisted chapter.
    public struct ReaderView: View {
        private let dependencies: FeaturesDependencies
        private let manga: MangaEntity
        private let chapters: [ChapterEntity]

        @State private var currentChapter: ChapterEntity
        @State private var viewModel: ReaderViewModel?
        @State private var challengeRoute: ChallengeRoute?
        @State private var isChromeVisible = true
        @State private var showingChapterPicker = false
        @State private var reloadToken = 0
        @AppStorage("readingDirection") private var readingDirection: ReadingDirection = .vertical
        @Environment(\.dismiss) private var dismiss

        public init(
            manga: MangaEntity,
            chapter: ChapterEntity,
            chapters: [ChapterEntity] = [],
            dependencies: FeaturesDependencies
        ) {
            self.dependencies = dependencies
            self.manga = manga
            self.chapters = chapters.isEmpty ? manga.chaptersInReadingOrder : chapters
            self._currentChapter = State(initialValue: chapter)

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
            readerBody(viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { toggleChrome() }
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isChromeVisible {
                        topBar(viewModel)
                            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isChromeVisible {
                        bottomBar(viewModel)
                            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(Color.black.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
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

        @ViewBuilder
        private func readerBody(_ viewModel: ReaderViewModel) -> some View {
            if viewModel.isLoading {
                ProgressView("Loading pages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.pages.isEmpty {
                ContentUnavailableView(
                    "No Pages",
                    systemImage: "doc.richtext",
                    description: Text("This chapter has no readable pages.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if readingDirection == .vertical {
                verticalReader(viewModel)
            } else {
                pagedReader(viewModel)
            }
        }

        private func toggleChrome() {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChromeVisible.toggle()
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
                            placeholderIcon: "photo",
                            reloadID: reloadToken
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
                        placeholderIcon: "photo",
                        reloadID: reloadToken
                    )
                    .tag(index)
                    .padding(.horizontal)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, readingDirection.layoutDirection)
        }

        // MARK: - Chrome

        /// Top bar anchored to the top edge: back to the series and page count.
        private func topBar(_ viewModel: ReaderViewModel) -> some View {
            HStack(spacing: 12) {
                Button {
                    closeReader(viewModel)
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back to manga")

                Spacer(minLength: 0)

                Text("\(viewModel.pageNumber) / \(viewModel.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    reloadImages(viewModel)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Reload images")
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.35)
            }
        }

        /// Bottom bar anchored to the bottom edge: chapter navigation and picker.
        private func bottomBar(_ viewModel: ReaderViewModel) -> some View {
            HStack(spacing: 8) {
                Button {
                    openChapter(previousChapter)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(previousChapter == nil)
                .opacity(previousChapter == nil ? 0.35 : 1)
                .accessibilityLabel("Previous chapter")

                Button {
                    showingChapterPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(currentChapter.title ?? Self.chapterLabel(for: currentChapter))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Select chapter")

                Button {
                    openChapter(nextChapter)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(nextChapter == nil)
                .opacity(nextChapter == nil ? 0.35 : 1)
                .accessibilityLabel("Next chapter")
            }
            .padding(.horizontal, 8)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Divider().opacity(0.35)
            }
            .sheet(isPresented: $showingChapterPicker) {
                ChapterPickerView(
                    chapters: chapters,
                    currentChapter: currentChapter,
                    onSelect: { chapter in
                        showingChapterPicker = false
                        openChapter(chapter)
                    }
                )
            }
        }

        private var currentChapterIndex: Int? {
            chapters.firstIndex { $0.id == currentChapter.id }
        }

        private var previousChapter: ChapterEntity? {
            guard let index = currentChapterIndex, index > 0 else { return nil }
            return chapters[index - 1]
        }

        private var nextChapter: ChapterEntity? {
            guard let index = currentChapterIndex, chapters.indices.contains(index + 1) else {
                return nil
            }
            return chapters[index + 1]
        }

        private func closeReader(_ viewModel: ReaderViewModel) {
            Task {
                await viewModel.flushProgress()
                dismiss()
            }
        }

        /// Re-fetches the chapter pages and retries every image.
        ///
        /// Some sites occasionally return broken pages on the first request.
        /// The token forces the image views to run their request again even
        /// when the URL did not change; failed downloads are not cached, so
        /// they are requested from the site again.
        private func reloadImages(_ viewModel: ReaderViewModel) {
            Task {
                reloadToken += 1
                await viewModel.reload()
            }
        }

        private func openChapter(_ chapter: ChapterEntity?) {
            guard let chapter, chapter.id != currentChapter.id else { return }
            guard let pageRepository = dependencies.pageRepository,
                let readingProgressRepository = dependencies.readingProgressRepository
            else {
                return
            }

            Task {
                await viewModel?.flushProgress()

                let newViewModel = ReaderViewModel(
                    manga: manga,
                    chapter: chapter,
                    pageRepository: pageRepository,
                    readingProgressRepository: readingProgressRepository,
                    mangaRepository: dependencies.mangaRepository,
                    chapterPagesProvider: dependencies.chapterPagesProvider
                )
                currentChapter = chapter
                viewModel = newViewModel
                withAnimation(.easeInOut(duration: 0.2)) {
                    isChromeVisible = true
                }
                await newViewModel.load()
            }
        }

        private static func chapterLabel(for chapter: ChapterEntity) -> String {
            guard let number = chapter.number else { return "Chapter" }
            return "Chapter \(String(format: "%g", number))"
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

    /// Sheet listing every chapter of the series, with the current one marked.
    private struct ChapterPickerView: View {
        let chapters: [ChapterEntity]
        let currentChapter: ChapterEntity
        let onSelect: (ChapterEntity) -> Void

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List(chapters) { chapter in
                    Button {
                        onSelect(chapter)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title ?? Self.label(for: chapter))
                                    .foregroundStyle(.primary)
                                if chapter.title != nil, let number = chapter.number,
                                    chapter.title != Self.label(for: number)
                                {
                                    Text(Self.label(for: number))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 0)

                            if chapter.id == currentChapter.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Chapters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }

        private static func label(for chapter: ChapterEntity) -> String {
            guard let number = chapter.number else { return "Chapter" }
            return label(for: number)
        }

        private static func label(for number: Double) -> String {
            "Chapter \(String(format: "%g", number))"
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
