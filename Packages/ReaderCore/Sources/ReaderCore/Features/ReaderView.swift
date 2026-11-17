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
        /// Becomes true once the vertical reader restored the saved page.
        ///
        /// Scroll updates are ignored until then: the first layout reports the
        /// top row, which would otherwise overwrite the restored index before
        /// the scroll view has moved to it.
        @State private var didRestoreScroll = false
        /// Page the reader opens at. Captured once, so a reload keeps the
        /// current page instead of returning to the entry point.
        private let startPosition: ReaderStartPosition
        @AppStorage("readingDirection") private var readingDirection: ReadingDirection = .vertical
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dismiss) private var dismiss

        /// Fallback portrait ratio used until a page reports its real size.
        private static let defaultPageAspectRatio: CGFloat = 0.7
        private static let scrollCoordinateSpace = "readerVerticalScroll"
        /// Fraction of the viewport added below the last page so it can be
        /// scrolled past the bottom edge.
        private static let endOverscrollFraction: CGFloat = 0.35

        public init(
            manga: MangaEntity,
            chapter: ChapterEntity,
            chapters: [ChapterEntity] = [],
            dependencies: FeaturesDependencies,
            startPosition: ReaderStartPosition = .restore
        ) {
            self.dependencies = dependencies
            self.manga = manga
            self.chapters = chapters.isEmpty ? manga.chaptersInReadingOrder : chapters
            self._currentChapter = State(initialValue: chapter)
            self.startPosition = startPosition

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
                        chapterPagesProvider: dependencies.chapterPagesProvider,
                        startPosition: startPosition
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
                .background(AppColor.readerCanvas)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { toggleChrome() }
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isChromeVisible {
                        topBar(viewModel)
                            .background { chromeGlass(ignoring: .top) }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isChromeVisible {
                        VStack(spacing: 0) {
                            chapterProgressBar(viewModel)
                            bottomBar(viewModel)
                        }
                        .background { chromeGlass(ignoring: .bottom) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(AppColor.readerCanvas.ignoresSafeArea())
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
                .sheet(isPresented: $showingChapterPicker) {
                    // Presented alongside the other sheets rather than from
                    // inside the bottom bar, so it stacks above the chrome.
                    ChapterPickerView(
                        chapters: chapters,
                        currentChapter: currentChapter,
                        onSelect: { chapter in
                            showingChapterPicker = false
                            openChapter(chapter)
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
            // Keep the pages on screen during a reload: swapping them for a
            // spinner would destroy the scroll view, lose the position and
            // tear down every decoded image.
            if viewModel.isLoading && viewModel.pages.isEmpty {
                // The canvas is black in dark mode and light gray in light
                // mode, so the label must not rely on the system default:
                // it follows the on-surface token that contrasts with both.
                ProgressView("Loading pages…")
                    .tint(AppColor.primary)
                    .foregroundStyle(AppColor.onSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.pages.isEmpty {
                ContentUnavailableView(
                    "No Pages",
                    systemImage: "doc.richtext",
                    description: Text("This chapter has no readable pages.")
                )
                .foregroundStyle(AppColor.onSurface)
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
        ///
        /// Every row reserves the page's real aspect ratio (falling back to a
        /// portrait default until the first decode reports the size), so the
        /// content height never collapses while rows leave and re-enter the
        /// lazy stack. The page counter follows the row that covers the top
        /// edge of the viewport instead of relying on `onAppear`, which fires
        /// for prefetched rows and can race itself.
        ///
        /// Pages do not share a ratio, so a short last image can never reach
        /// the top edge. A footer adds the overscroll that lets it be pushed
        /// up, and the counter treats a fully visible last page as the end of
        /// the chapter.
        private func verticalReader(_ viewModel: ReaderViewModel) -> some View {
            GeometryReader { container in
                ScrollViewReader { proxy in
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
                                    reloadID: reloadToken,
                                    reservedAspectRatio: Self.aspectRatio(for: page),
                                    onImageSize: { size in
                                        Task {
                                            await viewModel.recordPageSize(
                                                index: index,
                                                width: Int(size.width.rounded()),
                                                height: Int(size.height.rounded())
                                            )
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity)
                                .background {
                                    GeometryReader { geometry in
                                        let frame = geometry.frame(
                                            in: .named(Self.scrollCoordinateSpace))
                                        Color.clear.preference(
                                            key: ReaderPageFrameKey.self,
                                            value: [
                                                index: ReaderRowFrame(
                                                    minY: Double(frame.minY),
                                                    maxY: Double(frame.maxY)
                                                )
                                            ]
                                        )
                                    }
                                }
                            }

                            // Lets the last page scroll past the bottom edge, so
                            // a short final image can be read without being
                            // pinned to the bottom of the screen.
                            Color.clear
                                .frame(height: container.size.height * Self.endOverscrollFraction)
                        }
                        .onPreferenceChange(ReaderPageFrameKey.self) { frames in
                            updateCurrentPage(
                                from: frames,
                                viewportHeight: container.size.height,
                                viewModel: viewModel
                            )
                        }
                    }
                    .coordinateSpace(name: Self.scrollCoordinateSpace)
                    .scrollIndicators(.hidden)
                    .id(viewModel.chapter.id)
                    .onAppear {
                        restoreScrollPosition(
                            with: proxy,
                            viewport: container.size,
                            viewModel: viewModel
                        )
                    }
                    .onChange(of: viewModel.pages.count) { _, _ in
                        // The first `onAppear` runs while the page list is still
                        // loading, so the restore also has to retry once it
                        // arrives.
                        restoreScrollPosition(
                            with: proxy,
                            viewport: container.size,
                            viewModel: viewModel
                        )
                    }
                }
            }
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
                        reloadID: reloadToken,
                        onImageSize: { size in
                            Task {
                                await viewModel.recordPageSize(
                                    index: index,
                                    width: Int(size.width.rounded()),
                                    height: Int(size.height.rounded())
                                )
                            }
                        }
                    )
                    .tag(index)
                    .padding(.horizontal)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, readingDirection.layoutDirection)
        }

        /// Reserved width/height ratio for a page row.
        private static func aspectRatio(for page: PageEntity) -> CGFloat {
            guard let width = page.width, let height = page.height, width > 0, height > 0 else {
                return defaultPageAspectRatio
            }
            return CGFloat(width) / CGFloat(height)
        }

        /// Tracks the page that covers the top edge of the vertical reader.
        private func updateCurrentPage(
            from frames: [Int: ReaderRowFrame],
            viewportHeight: CGFloat,
            viewModel: ReaderViewModel
        ) {
            // Ignore layout reports until the saved page has been restored:
            // the first layout always reports the top row and would otherwise
            // pull the reader back to the beginning.
            guard didRestoreScroll, viewportHeight > 0, !viewModel.pages.isEmpty else { return }

            let lastIndex = viewModel.pages.count - 1
            guard
                let index = ReaderViewModel.currentPageIndex(
                    minYs: frames.mapValues(\.minY),
                    lastPageIndex: lastIndex,
                    lastPageBottom: frames[lastIndex]?.maxY,
                    viewportHeight: Double(viewportHeight)
                )
            else { return }

            let fraction = Self.pageOffset(for: frames[index])

            guard
                index != viewModel.currentPageIndex
                    || abs(fraction - viewModel.currentPageOffset) > 0.001
            else { return }
            Task { await viewModel.setPosition(index: index, fraction: fraction) }
        }

        /// How far the page has scrolled past the top edge, from 0 to 1.
        private static func pageOffset(for frame: ReaderRowFrame?) -> Double {
            guard let frame else { return 0 }
            let height = frame.maxY - frame.minY
            guard height > 0 else { return 0 }
            return min(max(-frame.minY / height, 0), 1)
        }

        /// Moves the vertical reader to the saved page after the first layout.
        ///
        /// A page can be taller than the screen, so restoring its top would
        /// lose the place inside a long strip. Scrolling to the page with a
        /// fractional anchor moves to the same point inside the row:
        /// aligning both views at `fraction` shifts the content by
        /// `fraction * (rowHeight - viewportHeight)`.
        private func restoreScrollPosition(
            with proxy: ScrollViewProxy,
            viewport: CGSize,
            viewModel: ReaderViewModel
        ) {
            guard !didRestoreScroll else { return }
            // Pages load asynchronously: wait for the list instead of marking
            // the restore as done against an empty stack.
            guard !viewModel.pages.isEmpty else { return }

            let index = viewModel.currentPageIndex
            guard viewModel.pages.indices.contains(index) else {
                didRestoreScroll = true
                return
            }

            let pageID = viewModel.pages[index].id
            let anchorY = ReaderViewModel.scrollAnchor(
                for: viewModel.currentPageOffset,
                pageHeight: Double(estimatedHeight(of: viewModel.pages[index], viewport: viewport)),
                viewport: Double(viewport.height)
            )

            guard anchorY > 0.001 || index > 0 else {
                didRestoreScroll = true
                return
            }

            Task { @MainActor in
                // Let the lazy stack build its first rows before jumping to a
                // page that may be far down the chapter.
                await Task.yield()
                proxy.scrollTo(pageID, anchor: UnitPoint(x: 0, y: anchorY))
                await Task.yield()
                didRestoreScroll = true
            }
        }

        /// Height a page row occupies at the current viewport width.
        private func estimatedHeight(of page: PageEntity, viewport: CGSize) -> CGFloat {
            guard viewport.width > 0 else { return 0 }
            return viewport.width / Self.aspectRatio(for: page)
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

        /// Background for the reader chrome.
        ///
        /// Light mode keeps the original thin material. In dark mode the bar
        /// has to stay dark regardless of the page behind it: over a white
        /// chapter a thin material washed out and the controls disappeared.
        private func chromeGlass(ignoring edges: Edge.Set) -> some View {
            Group {
                if colorScheme == .dark {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        Color.black.opacity(0.35)
                    }
                    .environment(\.colorScheme, .dark)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .ignoresSafeArea(edges: edges)
        }

        /// Slim bar above the bottom bar that fills as the chapter is read.
        ///
        /// Mirrors the per-chapter progress shown in the series details, so the
        /// reader always shows how far into the chapter it is.
        private func chapterProgressBar(_ viewModel: ReaderViewModel) -> some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                    Rectangle()
                        .fill(AppColor.primary)
                        .frame(width: geometry.size.width * viewModel.progress)
                }
            }
            .frame(height: 3)
            .animation(.easeOut(duration: 0.15), value: viewModel.progress)
            .accessibilityElement()
            .accessibilityLabel("Chapter progress")
            .accessibilityValue("\(Int((viewModel.progress * 100).rounded())) percent")
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
                // Drop the decoded copies first: reloading exists to recover
                // from pages the site served wrong, so the views must decode
                // them again instead of reusing the cached bitmap.
                DecodedImageCache.shared.removeImages(for: viewModel.pages.map(\.imageURL))
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

                didRestoreScroll = false

                let newViewModel = ReaderViewModel(
                    manga: manga,
                    chapter: chapter,
                    pageRepository: pageRepository,
                    readingProgressRepository: readingProgressRepository,
                    mangaRepository: dependencies.mangaRepository,
                    chapterPagesProvider: dependencies.chapterPagesProvider,
                    startPosition: ReaderEntryPoint.manualStart(for: chapter)
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

        /// Warms the pages around the current one so a swipe or an upward
        /// scroll does not wait for the network. The prefetch is symmetric:
        /// scrolling back up is as common as reading forward. Pages already in
        /// flight are deduplicated by the pipeline, so repeated calls are cheap.
        private func prefetchAdjacentPages(_ viewModel: ReaderViewModel) async {
            guard let loader = dependencies.imageLoader else { return }
            let current = viewModel.currentPageIndex
            let indices = [current - 2, current - 1, current + 1, current + 2]
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

    /// Frame of a realised reader row, in the scroll view's coordinate space.
    private struct ReaderRowFrame: Equatable {
        let minY: Double
        let maxY: Double
    }

    /// Vertical extent of every realised reader row.
    private struct ReaderPageFrameKey: PreferenceKey {
        static let defaultValue: [Int: ReaderRowFrame] = [:]

        static func reduce(
            value: inout [Int: ReaderRowFrame],
            nextValue: () -> [Int: ReaderRowFrame]
        ) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    /// Sheet listing every chapter of the series, with the current one marked.
    private struct ChapterPickerView: View {
        let chapters: [ChapterEntity]
        let currentChapter: ChapterEntity
        let onSelect: (ChapterEntity) -> Void

        @Environment(\.dismiss) private var dismiss

        /// Height that shows at most five chapters, so the picker stays a
        /// small popup instead of taking over the screen.
        private var detentHeight: CGFloat {
            let visibleRows = min(max(chapters.count, 1), 5)
            return CGFloat(visibleRows) * 52 + 96
        }

        var body: some View {
            NavigationStack {
                ScrollViewReader { proxy in
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
                    .listStyle(.plain)
                    .task {
                        // Open on the current chapter instead of the top of the
                        // list: jumping backwards is the common case.
                        await Task.yield()
                        proxy.scrollTo(currentChapter.id, anchor: .center)
                    }
                }
                .navigationTitle("Chapters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .presentationDetents([.height(detentHeight)])
            .presentationDragIndicator(.visible)
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
