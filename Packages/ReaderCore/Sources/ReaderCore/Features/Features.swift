// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Main entry point for the Features module
    @MainActor
    public enum Features {
        /// Creates the main tab view for the app.
        public static func makeTabView(dependencies: FeaturesDependencies) -> some View {
            MainTabView(dependencies: dependencies)
        }
    }

    /// Main tab view with Library, Browse, Sites, and Settings
    private struct MainTabView: View {
        let dependencies: FeaturesDependencies
        @State private var selectedTab: Tab = .library
        @AppStorage("theme") private var theme: AppTheme = .system

        enum Tab: String, CaseIterable {
            case library = "Library"
            case browse = "Browse"
            case sites = "Sites"
            case settings = "Settings"

            var icon: String {
                switch self {
                case .library: return "books.vertical"
                case .browse: return "magnifyingglass"
                case .sites: return "globe"
                case .settings: return "gear"
                }
            }

            var selectedIcon: String {
                switch self {
                case .library: return "books.vertical.fill"
                case .browse: return "magnifyingglass"
                case .sites: return "globe.fill"
                case .settings: return "gear.fill"
                }
            }
        }

        var body: some View {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    LibraryView(dependencies: dependencies)
                }
                .tabItem {
                    Label(
                        Tab.library.rawValue,
                        systemImage: selectedTab == .library ? Tab.library.selectedIcon : Tab.library.icon
                    )
                }
                .tag(Tab.library)

                NavigationStack {
                    SiteSearchView(dependencies: dependencies)
                }
                .tabItem {
                    Label(
                        Tab.browse.rawValue,
                        systemImage: selectedTab == .browse ? Tab.browse.selectedIcon : Tab.browse.icon
                    )
                }
                .tag(Tab.browse)

                NavigationStack {
                    SitesView(dependencies: dependencies)
                }
                .tabItem {
                    Label(
                        Tab.sites.rawValue,
                        systemImage: selectedTab == .sites ? Tab.sites.selectedIcon : Tab.sites.icon
                    )
                }
                .tag(Tab.sites)

                NavigationStack {
                    SettingsView(dependencies: dependencies)
                }
                .tabItem {
                    Label(
                        Tab.settings.rawValue,
                        systemImage: selectedTab == .settings ? Tab.settings.selectedIcon : Tab.settings.icon
                    )
                }
                .tag(Tab.settings)
            }
            .preferredColorScheme(theme.colorScheme)
            .task {
                // Apply the theme-declared CDN referrer map before the first
                // image load; runtime learning stays as the fallback.
                await dependencies.registerThemeReferrerHeaders()
            }
        }
    }

    /// Settings view
    private struct SettingsView: View {
        let dependencies: FeaturesDependencies
        @AppStorage("autoUpdate") private var autoUpdate: Bool = true
        @AppStorage("readingDirection") private var readingDirection: ReadingDirection = .vertical
        @AppStorage("theme") private var theme: AppTheme = .system
        @State private var showingClearCacheConfirmation = false

        private var appVersion: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        }

        var body: some View {
            Form {
                Section("Reading") {
                    Picker("Reading Direction", selection: $readingDirection) {
                        ForEach(ReadingDirection.allCases) { direction in
                            Text(direction.rawValue).tag(direction)
                        }
                    }

                    Toggle("Auto-update library", isOn: $autoUpdate)
                }

                Section("Storage") {
                    Button("Clear image cache", systemImage: "trash") {
                        showingClearCacheConfirmation = true
                    }
                }

                Section("Adapters") {
                    if let adapterStore = dependencies.adapterStore {
                        NavigationLink("Repositories and adapters") {
                            AdapterManagementView(
                                store: adapterStore,
                                siteProfileRepository: dependencies.siteProfileRepository
                            )
                        }
                    } else {
                        Text("Adapter management is unavailable.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    if let privacyURL = URL(string: "https://blankgrimoire.dev/privacy") {
                        Link("Privacy Policy", destination: privacyURL)
                    }
                    if let sourceURL = URL(string: "https://github.com/BlankGrimoire/BlankGrimoire-iOS") {
                        Link("Source Code", destination: sourceURL)
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear cached images?",
                isPresented: $showingClearCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear cache", role: .destructive) {
                    guard let imageLoader = dependencies.imageLoader else { return }
                    Task {
                        await imageLoader.clearCache()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Reading direction enum
    enum ReadingDirection: String, CaseIterable, Identifiable {
        case vertical = "Vertical"
        case horizontalRightToLeft = "Right to Left"
        case horizontalLeftToRight = "Left to Right"

        var id: String { rawValue }

    }

    /// App theme enum
    enum AppTheme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    #if DEBUG
        #Preview {
            MainTabView(dependencies: .preview)
        }
    #endif
#endif
