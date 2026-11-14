// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Sites management view - add/remove sites, configure site profiles
    public struct SitesView: View {
        let dependencies: FeaturesDependencies
        @State private var viewModel: SitesViewModel

        public init(dependencies: FeaturesDependencies) {
            self.dependencies = dependencies
            self._viewModel = State(
                initialValue: SitesViewModel(
                    siteProfileRepository: dependencies.siteProfileRepository,
                    themeSource: dependencies.themeSource,
                    themeDetector: dependencies.themeDetector,
                    mangaRepository: dependencies.mangaRepository,
                    chapterRepository: dependencies.chapterRepository,
                    pageRepository: dependencies.pageRepository,
                    readingProgressRepository: dependencies.readingProgressRepository,
                    bookmarkRepository: dependencies.bookmarkRepository
                )
            )
        }

        public var body: some View {
            List {
                Section {
                    Button {
                        viewModel.showingAddSite = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppColor.primary)
                            Text("Add Site")
                                .font(Typography.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xs)
                    }
                } header: {
                    Text("Add Site")
                }

                if !viewModel.siteProfiles.isEmpty {
                    Section {
                        ForEach(viewModel.siteProfiles) { profile in
                            NavigationLink {
                                SiteDetailView(
                                    profile: profile,
                                    viewModel: viewModel,
                                    imageLoader: dependencies.imageLoader
                                )
                            } label: {
                                SiteRowView(profile: profile, imageLoader: dependencies.imageLoader)
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                await viewModel.deleteProfiles(at: indexSet)
                            }
                        }
                    } header: {
                        Text("Configured Sites")
                    } footer: {
                        Text("Swipe to delete a site profile")
                            .font(Typography.caption1)
                    }
                } else {
                    Section {
                        VStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: "globe")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)

                            Text("No sites configured")
                                .font(Typography.title3)
                                .foregroundStyle(.secondary)

                            Text("Add a site to start building your library from the sources you choose")
                                .font(Typography.callout)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, DesignTokens.Spacing.xl)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.xl)
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Configured Sites")
                    }
                }
            }
            .navigationTitle("Sites")
            .refreshable {
                await viewModel.loadProfiles()
            }
            .task {
                await viewModel.loadProfiles()
            }
            .sheet(isPresented: $viewModel.showingAddSite) {
                AddSiteView(viewModel: viewModel)
            }
            .onChange(of: viewModel.showingAddSite) { _, isShowing in
                if !isShowing {
                    viewModel.lastError = nil
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.lastError != nil && !viewModel.showingAddSite },
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

    /// Row view for a site profile
    private struct SiteRowView: View {
        let profile: SiteProfile
        let imageLoader: (any ImageLoading)?

        var body: some View {
            HStack {
                SiteFaviconImage(baseURL: profile.baseURL, loader: imageLoader)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
                    .background(
                        AppColor.surfaceVariant,
                        in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(Typography.body)
                    Text(profile.baseURL)
                        .font(Typography.caption1)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(profile.themeID)
                    .font(Typography.caption1)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(AppColor.primary.opacity(0.1), in: Capsule())
                    .foregroundStyle(AppColor.primary)
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
    }

    /// Add site sheet
    private struct AddSiteView: View {
        @Bindable var viewModel: SitesViewModel
        @Environment(\.dismiss) private var dismiss

        @State private var url: String = ""
        @State private var name: String = ""
        @State private var challengeRoute: ChallengeRoute?

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Site URL (e.g. https://example.org)", text: $url)
                            .keyboardType(.URL)
                            .noAutoCapitalization()
                            .autocorrectionDisabled()
                            .onChange(of: url) {
                                viewModel.clearDetection()
                            }

                        TextField("Display Name (optional)", text: $name)
                    } header: {
                        Text("Site Information")
                    }

                    Section {
                        Button {
                            Task {
                                await viewModel.detectTheme(for: url)
                            }
                        } label: {
                            HStack {
                                if viewModel.isDetecting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                }
                                Text(viewModel.isDetecting ? "Detecting..." : "Detect Theme")
                            }
                        }
                        .disabled(viewModel.isDetecting || url.isEmpty)

                        if let result = viewModel.lastDetection {
                            Label(
                                "Detected: \(result.theme.name)",
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Score \(result.score)")
                                if !result.matchedSignals.isEmpty {
                                    Text(result.matchedSignals.joined(separator: ", "))
                                        .lineLimit(3)
                                }
                            }
                            .font(Typography.caption2)
                            .foregroundStyle(.secondary)
                        }

                        if let error = viewModel.lastError {
                            Text(error.localizedDescription)
                                .font(Typography.caption1)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Theme Detection")
                    }

                    Section {
                        if viewModel.availableThemes.isEmpty {
                            Text("No themes installed. Install a theme repository in Settings first.")
                                .font(Typography.caption1)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Theme", selection: $viewModel.selectedThemeID) {
                                ForEach(viewModel.availableThemes) { theme in
                                    Text(theme.name).tag(theme.id)
                                }
                            }
                        }
                    } header: {
                        Text("Theme")
                    }
                }
                .navigationTitle("Add Site")
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: viewModel.challengeURL) { _, challengeURL in
                    guard let challengeURL,
                        let host = challengeURL.host?.lowercased()
                    else {
                        return
                    }
                    challengeRoute = ChallengeRoute(url: challengeURL, allowedHosts: [host])
                }
                .sheet(item: $challengeRoute) { route in
                    ChallengeView(
                        url: route.url,
                        allowedHosts: route.allowedHosts
                    ) { outcome in
                        challengeRoute = nil
                        if outcome == .completed {
                            Task {
                                await viewModel.detectTheme(for: url)
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            viewModel.lastError = nil
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                let added = await viewModel.addSite(
                                    url: url,
                                    name: name,
                                    themeID: viewModel.selectedThemeID
                                )
                                if added {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(
                            url.isEmpty
                                || viewModel.selectedThemeID.isEmpty
                                || viewModel.isDetecting
                        )
                    }
                }
            }
        }

        private struct ChallengeRoute: Identifiable {
            let id = UUID()
            let url: URL
            let allowedHosts: Set<String>

            init(url: URL, allowedHosts: [String]) {
                self.url = url
                self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
            }
        }
    }

    /// Site detail view
    private struct SiteDetailView: View {
        let profile: SiteProfile
        @Bindable var viewModel: SitesViewModel
        let imageLoader: (any ImageLoading)?

        @State private var isEnabled: Bool
        @State private var automaticCookies: Bool
        @State private var selectedThemeID: String
        @State private var showingChallenge = false

        init(profile: SiteProfile, viewModel: SitesViewModel, imageLoader: (any ImageLoading)?) {
            self.profile = profile
            self.viewModel = viewModel
            self.imageLoader = imageLoader
            self._isEnabled = State(initialValue: profile.isEnabled)
            self._automaticCookies = State(initialValue: profile.cookieHandling == .automatic)
            self._selectedThemeID = State(initialValue: profile.themeID)
        }

        private var themeVersion: String? {
            viewModel.availableThemes.first { $0.id == selectedThemeID }?.version
                ?? (selectedThemeID == profile.themeID ? profile.themeVersion : nil)
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text(profile.baseURL)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Theme", selection: $selectedThemeID) {
                        ForEach(viewModel.availableThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                        if !viewModel.availableThemes.contains(where: { $0.id == selectedThemeID }) {
                            Text(selectedThemeID).tag(selectedThemeID)
                        }
                    }
                    .onChange(of: selectedThemeID) { _, newValue in
                        guard newValue != profile.themeID else { return }
                        Task { await viewModel.setTheme(newValue, for: profile) }
                    }

                    if let version = themeVersion {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(version)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Site Info")
                } footer: {
                    Text("Theme detection is heuristic. Choose the theme that extracts this site correctly.")
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                        .onChange(of: isEnabled) { _, newValue in
                            Task {
                                await viewModel.setEnabled(newValue, for: profile)
                            }
                        }

                    Toggle("Automatic Cookie Handling", isOn: $automaticCookies)
                        .onChange(of: automaticCookies) { _, newValue in
                            Task {
                                await viewModel.setCookieHandling(
                                    newValue ? .automatic : .none,
                                    for: profile
                                )
                            }
                        }
                } header: {
                    Text("Settings")
                }

                Section("Verification") {
                    if let url = URL(string: profile.baseURL) {
                        Button("Open visible verification browser", systemImage: "safari") {
                            showingChallenge = true
                        }
                        .sheet(isPresented: $showingChallenge) {
                            ChallengeView(
                                url: url,
                                allowedHosts: Set([url.host?.lowercased()].compactMap { $0 })
                            )
                        }
                    }
                }

                Section {
                    NavigationLink("Selector Overrides") {
                        SelectorOverridesView(profile: profile, viewModel: viewModel)
                    }
                } header: {
                    Text("Customization")
                }
            }
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Editable selector overrides
    private struct SelectorOverridesView: View {
        let profile: SiteProfile
        @Bindable var viewModel: SitesViewModel
        @Environment(\.dismiss) private var dismiss

        @State private var searchPath: String
        @State private var searchItem: String
        @State private var searchTitle: String
        @State private var searchLink: String
        @State private var searchCover: String
        @State private var detailsTitle: String
        @State private var detailsCover: String
        @State private var chapterItem: String
        @State private var chapterLink: String

        init(profile: SiteProfile, viewModel: SitesViewModel) {
            self.profile = profile
            self.viewModel = viewModel

            let overrides = profile.selectorOverrides
            self._searchPath = State(initialValue: overrides.search?.path ?? "")
            self._searchItem = State(initialValue: overrides.search?.item ?? "")
            self._searchTitle = State(initialValue: overrides.search?.title ?? "")
            self._searchLink = State(initialValue: overrides.search?.link ?? "")
            self._searchCover = State(initialValue: overrides.search?.cover ?? "")
            self._detailsTitle = State(initialValue: overrides.details?.title ?? "")
            self._detailsCover = State(initialValue: overrides.details?.cover ?? "")
            self._chapterItem = State(initialValue: overrides.chapters?.item ?? "")
            self._chapterLink = State(initialValue: overrides.chapters?.link ?? "")
        }

        var body: some View {
            Form {
                Section {
                    TextField("Path", text: $searchPath)
                    TextField("Item", text: $searchItem)
                    TextField("Title", text: $searchTitle)
                    TextField("Link", text: $searchLink)
                    TextField("Cover", text: $searchCover)
                } header: {
                    Text("Search")
                }

                Section {
                    TextField("Title", text: $detailsTitle)
                    TextField("Cover", text: $detailsCover)
                } header: {
                    Text("Details")
                }

                Section {
                    TextField("Item", text: $chapterItem)
                    TextField("Link", text: $chapterLink)
                } header: {
                    Text("Chapters")
                }

                Section {
                    if let strategies = profile.selectorOverrides.pages?.strategies, !strategies.isEmpty {
                        ForEach(strategies, id: \.self) { strategy in
                            Text(strategy.displayString)
                                .font(Typography.caption1)
                        }
                    } else {
                        Text("The theme defaults are used for page extraction.")
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Pages")
                } footer: {
                    Text("Leave a field blank to keep the theme default.")
                        .font(Typography.caption1)
                }
            }
            .navigationTitle("Selector Overrides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.updateOverrides(editedOverrides, for: profile)
                            dismiss()
                        }
                    }
                }
            }
        }

        private var editedOverrides: ThemeSelectorsOverrides {
            let original = profile.selectorOverrides

            return ThemeSelectorsOverrides(
                search: .init(
                    path: nonEmpty(searchPath) ?? original.search?.path,
                    item: nonEmpty(searchItem) ?? original.search?.item,
                    title: nonEmpty(searchTitle) ?? original.search?.title,
                    link: nonEmpty(searchLink) ?? original.search?.link,
                    cover: nonEmpty(searchCover) ?? original.search?.cover,
                    nextPage: original.search?.nextPage
                ),
                details: .init(
                    title: nonEmpty(detailsTitle) ?? original.details?.title,
                    cover: nonEmpty(detailsCover) ?? original.details?.cover,
                    synopsis: original.details?.synopsis,
                    authors: original.details?.authors,
                    artists: original.details?.artists,
                    altTitles: original.details?.altTitles,
                    tags: original.details?.tags,
                    status: original.details?.status,
                    contentRating: original.details?.contentRating
                ),
                chapters: .init(
                    item: nonEmpty(chapterItem) ?? original.chapters?.item,
                    link: nonEmpty(chapterLink) ?? original.chapters?.link,
                    title: original.chapters?.title,
                    date: original.chapters?.date,
                    order: original.chapters?.order ?? "desc"
                ),
                pages: original.pages,
                attribution: original.attribution
            )
        }

        private func nonEmpty(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    extension View {
        @ViewBuilder
        fileprivate func noAutoCapitalization() -> some View {
            #if os(iOS)
                textInputAutocapitalization(.never)
            #else
                self
            #endif
        }
    }

    #if DEBUG
        #Preview {
            NavigationStack {
                SitesView(dependencies: .preview)
            }
        }
    #endif
#endif
