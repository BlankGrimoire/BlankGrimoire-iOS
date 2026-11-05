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
            let schema = Schema([
                MangaEntity.self,
                ChapterEntity.self,
                PageEntity.self,
                ReadingProgressEntity.self,
                BookmarkEntity.self,
                SiteProfileEntity.self,
                TrustedRepositoryEntity.self,
                InstalledAdapterEntity.self,
            ])
            let configuration = ModelConfiguration(schema: schema)
            let container = try ModelContainer(for: schema, configurations: [configuration])

            let persistence = try SwiftDataPersistenceManager(container: container)

            // The adapter repository allowlist will be made configurable in
            // IOS-10. Until then, keep a restrictive placeholder policy.
            let adapterRequestHandler = PluginRequestHandler(
                policy: SiteNetworkPolicy(
                    baseURL: "https://example.org",
                    allowedHosts: ["example.org"]
                )
            )
            let adapterStore = try DefaultAdapterStore(
                modelContainer: container,
                requestHandler: adapterRequestHandler
            )

            self.container = container
            self.dependencies = FeaturesDependencies(
                mangaRepository: persistence.mangas,
                chapterRepository: persistence.chapters,
                siteProfileRepository: persistence.siteProfiles,
                themeSource: LocalThemeSource(adapterStore: adapterStore),
                themeDetector: DefaultSiteThemeDetector(adapterStore: adapterStore),
                imageLoader: PipelineImageLoader()
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
