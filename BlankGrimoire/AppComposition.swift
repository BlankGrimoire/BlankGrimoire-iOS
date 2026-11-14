// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import SwiftData

/// Builds the app's object graph.
///
/// The App target owns composition; separating it from `App.init` keeps the
/// graph testable with an in-memory store.
@MainActor
enum AppComposition {
    static func makeModelContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        try BlankGrimoireSchema.makeContainer(isStoredInMemoryOnly: isStoredInMemoryOnly)
    }

    static func makeDependencies(container: ModelContainer) throws -> FeaturesDependencies {
        let persistence = try SwiftDataPersistenceManager(container: container)

        // Repository requests derive a host-scoped policy from each
        // user-approved HTTPS repository URL.
        let adapterStore = try DefaultAdapterStore(modelContainer: container)
        // Older builds stored the repository display name as the trust URL.
        // Those rows can never match a request and are removed once.
        try adapterStore.purgeInvalidTrustedRepositories()

        // Remote theme repository. The URL comes from Info.plist so a build
        // can point at another signed repository without code changes.
        let themeRepositoryURL = AppConfiguration.themesRepositoryURL()
        let themeRequestHandler = PluginRequestHandler(
            policy: AppConfiguration.themesRepositoryPolicy(for: themeRepositoryURL)
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

        // Image pipeline configured with referrer headers from the active theme adapter.
        // The referrer headers are loaded from the theme adapter's manifest.
        let imageLoader = PipelineImageLoader(configuration: ImagePipelineConfiguration())

        return FeaturesDependencies(
            mangaRepository: persistence.mangas,
            chapterRepository: persistence.chapters,
            pageRepository: persistence.pages,
            readingProgressRepository: persistence.readingProgress,
            bookmarkRepository: persistence.bookmarks,
            siteProfileRepository: persistence.siteProfiles,
            themeSource: CompositeThemeSource(sources: [localThemeSource, remoteThemeSource]),
            themeDetector: DefaultSiteThemeDetector(adapterStore: adapterStore),
            imageLoader: imageLoader,
            adapterStore: adapterStore,
            catalogService: catalogService,
            chapterPagesProvider: chapterPagesProvider
        )
    }
}
