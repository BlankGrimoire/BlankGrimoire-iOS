// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import Foundation
    import SwiftUI

    /// Read-only preview of a search hit that is not in the library yet.
    ///
    /// The adapter's `getDetails` and `getChapters` output is fetched without
    /// persisting anything, so the user can inspect a series before importing
    /// it.
    @MainActor
    struct SearchResultDetailView: View {
        let result: SiteSearchResult
        private let dependencies: FeaturesDependencies

        @State private var details: MangaDetails?
        @State private var chapters: [Chapter] = []
        @State private var isLoading = false
        @State private var isImporting = false
        @State private var isImported: Bool
        @State private var lastError: Error?

        init(
            result: SiteSearchResult,
            alreadyImported: Bool = false,
            dependencies: FeaturesDependencies
        ) {
            self.result = result
            self.dependencies = dependencies
            self._isImported = State(initialValue: alreadyImported)
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    header

                    if isLoading && details == nil {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            ProgressView()
                            Text("Loading details…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let details {
                        if let synopsis = details.synopsis, !synopsis.isEmpty {
                            synopsisSection(synopsis)
                        }

                        if let genres = details.genres, !genres.isEmpty {
                            badgeSection(title: "Genres", values: genres, color: AppColor.primary)
                        }

                        if let tags = details.tags, !tags.isEmpty {
                            badgeSection(title: "Tags", values: tags, color: AppColor.secondary)
                        }

                        creatorsSection(details)
                        chaptersSection
                        attributionSection(details)
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
            .navigationTitle(details?.title ?? result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    importAction
                }
            }
            .task { await load() }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { lastError != nil },
                    set: { isPresented in
                        if !isPresented {
                            lastError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    lastError = nil
                }
            } message: {
                Text(lastError?.localizedDescription ?? "")
            }
        }

        // MARK: - Sections

        private var header: some View {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                MangaCoverImage(
                    url: details?.coverURL ?? result.coverURL,
                    loader: dependencies.imageLoader,
                    siteBaseURL: result.siteURL
                )
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
                    Text(details?.title ?? result.title)
                        .font(Typography.title2.weight(.bold))
                        .lineLimit(3)

                    Text(result.siteName)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)

                    if let details {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Label(details.status.displayName, systemImage: statusIcon(for: details.status))
                            Label(
                                details.contentRating.displayName,
                                systemImage: ratingIcon(for: details.contentRating)
                            )
                        }
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)

                        if let altTitles = details.altTitles, !altTitles.isEmpty {
                            Text(altTitles.joined(separator: " · "))
                                .font(Typography.caption1)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }

                        if isImported {
                            Label("In Library", systemImage: "checkmark.circle.fill")
                                .font(Typography.caption1.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
        }

        private func synopsisSection(_ synopsis: String) -> some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Synopsis")
                    .font(Typography.headline)
                Text(synopsis)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
            .card()
        }

        private func badgeSection(title: String, values: [String], color: Color) -> some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(Typography.headline)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: DesignTokens.Spacing.xs)],
                    alignment: .leading,
                    spacing: DesignTokens.Spacing.xs
                ) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(Typography.caption1)
                            .lineLimit(1)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .frame(maxWidth: .infinity)
                            .background(color.opacity(0.1), in: Capsule())
                            .foregroundStyle(color)
                    }
                }
            }
        }

        @ViewBuilder
        private func creatorsSection(_ details: MangaDetails) -> some View {
            let authors = details.authors ?? []
            let artists = details.artists ?? []
            if !authors.isEmpty || !artists.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Creators")
                        .font(Typography.headline)

                    if !authors.isEmpty {
                        Label("Author: \(authors.joined(separator: ", "))", systemImage: "person.fill")
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                    }

                    if !artists.isEmpty {
                        Label("Artist: \(artists.joined(separator: ", "))", systemImage: "paintbrush.fill")
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var chaptersSection: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Import the series to read its chapters.")
                    .font(Typography.caption1.weight(.semibold))
                    .foregroundStyle(.red)

                Text("Chapters (\(chapters.count))")
                    .font(Typography.headline)

                if chapters.isEmpty {
                    Text(isLoading ? "Loading chapters…" : "No chapters are available for this series.")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(orderedChapters) { chapter in
                            HStack(spacing: DesignTokens.Spacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title ?? label(for: chapter))
                                        .font(Typography.body)
                                        .lineLimit(1)

                                    if chapter.title != nil, let number = chapter.number,
                                        chapter.title != label(for: number)
                                    {
                                        Text(label(for: number))
                                            .font(Typography.caption1)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                if let date = date(from: chapter.publishedAt) {
                                    Text(date, style: .date)
                                        .font(Typography.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(DesignTokens.Spacing.sm)
                            .background(AppColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func attributionSection(_ details: MangaDetails) -> some View {
            if let attribution = details.attribution {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("Source")
                        .font(Typography.headline)

                    Text(attribution.siteName)
                        .font(Typography.body)

                    if let credits = attribution.credits, !credits.isEmpty {
                        Text(credits)
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }

                    if let siteURL = SiteURL.normalizedURL(from: attribution.siteURL) {
                        Link(destination: siteURL) {
                            Label("Open on site", systemImage: "safari")
                        }
                        .font(Typography.callout.weight(.medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }

        // MARK: - Actions

        @ViewBuilder
        private var importAction: some View {
            if isImported {
                Label("In Library", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else if isImporting {
                ProgressView()
            } else {
                Button {
                    Task { await importResult() }
                } label: {
                    Label("Import", systemImage: "plus.circle")
                }
            }
        }

        private func load() async {
            guard details == nil, !isLoading else { return }
            guard let catalogService = dependencies.catalogService else {
                lastError = SiteBrowsingError.catalogUnavailable
                return
            }

            isLoading = true
            defer { isLoading = false }

            do {
                let fetched = try await catalogService.fetchDetails(result)
                details = fetched.details
                chapters = fetched.chapters
            } catch {
                lastError = error
            }
        }

        private func importResult() async {
            guard !isImporting else { return }
            guard let catalogService = dependencies.catalogService else {
                lastError = SiteBrowsingError.catalogUnavailable
                return
            }

            isImporting = true
            defer { isImporting = false }

            do {
                _ = try await catalogService.importManga(result)
                isImported = true
            } catch {
                lastError = error
            }
        }

        // MARK: - Formatting

        private var orderedChapters: [Chapter] {
            chapters.sorted { lhs, rhs in
                let left = lhs.number ?? .greatestFiniteMagnitude
                let right = rhs.number ?? .greatestFiniteMagnitude
                if left != right {
                    return left < right
                }
                return lhs.key < rhs.key
            }
        }

        private func label(for chapter: Chapter) -> String {
            guard let number = chapter.number else { return "Chapter" }
            return label(for: number)
        }

        private func label(for number: Double) -> String {
            "Chapter \(String(format: "%g", number))"
        }

        private func date(from value: ISODateString?) -> Date? {
            guard let value else { return nil }
            return Self.fractionalDateFormatter.date(from: value)
                ?? Self.dateFormatter.date(from: value)
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

        private static let fractionalDateFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        private static let dateFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
    }
#endif
