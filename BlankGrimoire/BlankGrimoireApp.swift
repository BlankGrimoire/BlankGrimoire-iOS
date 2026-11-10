// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import SwiftData
import SwiftUI

@main
struct BlankGrimoireApp: App {
    private let container: ModelContainer
    private let dependencies: FeaturesDependencies

    @MainActor
    init() {
        do {
            let schema = Schema(versionedSchema: BlankGrimoireSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: BlankGrimoireMigrationPlan.self,
                configurations: [configuration]
            )

            let persistence = try SwiftDataPersistenceManager(container: container)

            // Repository requests derive a host-scoped policy from each
            // user-approved HTTPS repository URL.
            let adapterStore = try DefaultAdapterStore(modelContainer: container)
            // Older builds stored the repository display name as the trust URL.
            // Those rows can never match a request and are removed once.
            try adapterStore.purgeInvalidTrustedRepositories()

            // Remote theme repository (GitHub Pages)
            let themeRepositoryURL = "https://blankgrimoire.github.io/BlankGrimoire-themes/index.json"
            let themeRequestHandler = PluginRequestHandler(
                policy: SiteNetworkPolicy(
                    baseURL: "https://blankgrimoire.github.io",
                    allowedHosts: ["blankgrimoire.github.io"]
                )
            )
            let remoteThemeSource = RemoteThemeSource(
                repositoryURL: themeRepositoryURL,
                requestHandler: themeRequestHandler
            )
            let localThemeSource = LocalThemeSource(adapterStore: adapterStore)

            // The catalog service searches every saved site through its
            // installed adapter, and the page provider loads chapter pages on
            // demand from the same adapter.
            let catalogService = SiteCatalogService(
                siteProfileRepository: persistence.siteProfiles,
                mangaRepository: persistence.mangas,
                chapterRepository: persistence.chapters,
                adapterStore: adapterStore
            )
            let chapterPagesProvider = DefaultChapterPagesProvider(
                pageRepository: persistence.pages,
                chapterRepository: persistence.chapters,
                siteProfileRepository: persistence.siteProfiles,
                adapterStore: adapterStore
            )
            self.container = container
            self.dependencies = FeaturesDependencies(
                mangaRepository: persistence.mangas,
                chapterRepository: persistence.chapters,
                pageRepository: persistence.pages,
                readingProgressRepository: persistence.readingProgress,
                bookmarkRepository: persistence.bookmarks,
                siteProfileRepository: persistence.siteProfiles,
                themeSource: CompositeThemeSource(sources: [localThemeSource, remoteThemeSource]),
                themeDetector: DefaultSiteThemeDetector(adapterStore: adapterStore),
                imageLoader: PipelineImageLoader(),
                adapterStore: adapterStore,
                catalogService: catalogService,
                chapterPagesProvider: chapterPagesProvider
            )
        } catch {
            fatalError("Unable to initialize BlankGrimoire: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
        .modelContainer(container)
    }
}
