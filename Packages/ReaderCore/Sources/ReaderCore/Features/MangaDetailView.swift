// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Flow layout for tags
    private struct FlowLayout: Layout {
        let spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let result = FlowResult(
                in: proposal.replacingUnspecifiedDimensions().width,
                subviews: subviews,
                spacing: spacing
            )
            return result.size
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) {
            let result = FlowResult(
                in: bounds.width,
                subviews: subviews,
                spacing: spacing
            )

            for (index, subview) in subviews.enumerated() {
                subview.place(
                    at: CGPoint(
                        x: result.positions[index].x + bounds.minX,
                        y: result.positions[index].y + bounds.minY
                    ),
                    proposal: ProposedViewSize(result.sizes[index])
                )
            }
        }

        private struct FlowResult {
            let positions: [CGPoint]
            let sizes: [CGSize]
            let size: CGSize

            init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
                var positions: [CGPoint] = []
                var sizes: [CGSize] = []
                var currentX: CGFloat = 0
                var currentY: CGFloat = 0
                var lineHeight: CGFloat = 0

                for subview in subviews {
                    let size = subview.sizeThatFits(.unspecified)
                    sizes.append(size)

                    if currentX + size.width > maxWidth && currentX > 0 {
                        currentX = 0
                        currentY += lineHeight + spacing
                        lineHeight = 0
                    }

                    positions.append(CGPoint(x: currentX, y: currentY))
                    currentX += size.width + spacing
                    lineHeight = max(lineHeight, size.height)
                }

                self.positions = positions
                self.sizes = sizes
                self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
            }
        }
    }

    /// Chapter row view
    private struct ChapterRowView: View {
        let chapter: ChapterEntity
        let isDownloaded: Bool
        let progress: Double
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(chapter.title ?? "Chapter \(chapter.number ?? 0)")
                                .font(Typography.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            if let number = chapter.number {
                                Text("Ch. \(number, specifier: "%.1f")")
                                    .font(Typography.caption1)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        if progress > 0 {
                            ProgressView(value: progress)
                                .tint(AppColor.primary)
                        }
                    }

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if isDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }

                        if let publishedAt = chapter.publishedAt {
                            Text(publishedAt, style: .date)
                                .font(Typography.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.tertiary)
                }
                .padding(DesignTokens.Spacing.sm)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
            }
            .buttonStyle(.plain)
        }
    }

    /// Manga detail view showing full information and chapters
    public struct MangaDetailView: View {
        let manga: MangaEntity
        let dependencies: FeaturesDependencies

        @State private var viewModel: MangaDetailViewModel
        @Environment(\.dismiss) private var dismiss

        public init(manga: MangaEntity, dependencies: FeaturesDependencies) {
            self.manga = manga
            self.dependencies = dependencies
            self._viewModel = State(
                initialValue: MangaDetailViewModel(
                    manga: manga,
                    chapterRepository: dependencies.chapterRepository,
                    mangaRepository: dependencies.mangaRepository
                )
            )
        }

        private var coverSection: some View {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                MangaCoverImage(url: manga.coverURL, loader: dependencies.imageLoader)
                    .frame(width: 120)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
                    .shadow(
                        color: .black.opacity(DesignTokens.Shadow.md.opacity),
                        radius: DesignTokens.Shadow.md.radius,
                        x: DesignTokens.Shadow.md.x,
                        y: DesignTokens.Shadow.md.y
                    )

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(manga.title)
                        .font(Typography.title2.weight(.bold))
                        .lineLimit(3)

                    HStack(spacing: DesignTokens.Spacing.md) {
                        Label(manga.status.displayName, systemImage: statusIcon(for: manga.status))
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)

                        Label(manga.contentRating.displayName, systemImage: ratingIcon(for: manga.contentRating))
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }

                    if let lastRead = manga.lastReadAt {
                        Text("Last read \(lastRead, style: .offset)")
                            .font(Typography.caption1)
                            .foregroundStyle(.tertiary)
                    }

                    if manga.readingProgress > 0 {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            HStack {
                                Text("Progress")
                                    .font(Typography.caption1)
                                Spacer()
                                Text("\(Int(manga.readingProgress * 100))%")
                                    .font(Typography.caption1.weight(.medium))
                            }

                            ProgressView(value: manga.readingProgress)
                                .tint(AppColor.primary)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
        }

        private var infoSection: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if !manga.altTitles.isEmpty {
                    Text("Alternative Titles")
                        .font(Typography.caption1.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(manga.altTitles, id: \.self) { altTitle in
                        Text(altTitle)
                            .font(Typography.caption1)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !manga.authors.isEmpty {
                    Text("Authors: \(manga.authors.joined(separator: ", "))")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                }

                if !manga.artists.isEmpty {
                    Text("Artists: \(manga.artists.joined(separator: ", "))")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private var synopsisSection: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Synopsis")
                    .font(Typography.headline)
                Text(manga.synopsis ?? "")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
            .card()
        }

        private var tagsSection: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Genres")
                    .font(Typography.headline)

                FlowLayout(spacing: DesignTokens.Spacing.xs) {
                    ForEach(manga.tags, id: \.self) { tag in
                        Text(tag)
                            .font(Typography.caption1)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(AppColor.primary.opacity(0.1), in: Capsule())
                            .foregroundStyle(AppColor.primary)
                    }
                }
            }
        }

        private var authorsSection: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if !manga.authors.isEmpty || !manga.artists.isEmpty {
                    Text("Creators")
                        .font(Typography.headline)

                    if !manga.authors.isEmpty {
                        Label("Author: \(manga.authors.joined(separator: ", "))", systemImage: "person.fill")
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                    }

                    if !manga.artists.isEmpty {
                        Label("Artist: \(manga.artists.joined(separator: ", "))", systemImage: "paintbrush.fill")
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var attributionSection: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                if let attribution = manga.attribution {
                    Text("Source")
                        .font(Typography.headline)

                    Text(attribution.siteName)
                        .font(Typography.body)

                    if let credits = attribution.credits, !credits.isEmpty {
                        Text(credits)
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }

                    if let siteURL = URL(string: attribution.siteURL) {
                        Link(destination: siteURL) {
                            Label("Open on site", systemImage: "safari")
                        }
                        .font(Typography.callout.weight(.medium))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }

        private var chaptersSection: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack {
                    Text("Chapters (\(viewModel.chapters.count))")
                        .font(Typography.headline)

                    Spacer()

                    if viewModel.isLoadingChapters {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if viewModel.chapters.isEmpty && !viewModel.isLoadingChapters {
                    ContentUnavailableView(
                        "No Chapters",
                        systemImage: "book.closed",
                        description: Text("No chapters are available for this series")
                    )
                } else {
                    LazyVStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(viewModel.chapters) { chapter in
                            ChapterRowView(
                                chapter: chapter,
                                isDownloaded: chapter.isDownloaded,
                                progress: chapter.readingProgressEntries.first?.progress ?? 0
                            ) {
                                Task { await viewModel.readChapter(chapter) }
                            }
                        }
                    }
                }
            }
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    coverSection
                    infoSection

                    if let synopsis = manga.synopsis, !synopsis.isEmpty {
                        synopsisSection
                    }

                    if !manga.tags.isEmpty {
                        tagsSection
                    }

                    authorsSection

                    if manga.attribution != nil {
                        attributionSection
                    }

                    chaptersSection
                }
                .padding(DesignTokens.Spacing.md)
            }
            .navigationTitle(manga.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.toggleFavorite() }
                    } label: {
                        Image(systemName: manga.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(manga.isFavorite ? .red : .secondary)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Mark All Read", systemImage: "checkmark.circle") {
                            Task { await viewModel.markAllAsRead() }
                        }
                        Divider()
                        Button("Remove from Library", systemImage: "trash", role: .destructive) {
                            Task {
                                if await viewModel.deleteManga() {
                                    dismiss()
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadChapters()
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

        private func statusIcon(for status: MangaStatus) -> String {
            switch status {
            case .ongoing: return "circle.fill"
            case .completed: return "checkmark.circle.fill"
            case .hiatus: return "pause.circle.fill"
            case .cancelled: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }

        private func ratingIcon(for rating: ContentRating) -> String {
            switch rating {
            case .safe: return "leaf.fill"
            case .suggestive: return "exclamationmark.triangle.fill"
            case .mature: return "exclamationmark.octagon.fill"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    #if DEBUG
        #Preview {
            NavigationStack {
                MangaDetailView(manga: MangaEntity.previewData[0], dependencies: .preview)
            }
        }
    #endif
#endif
