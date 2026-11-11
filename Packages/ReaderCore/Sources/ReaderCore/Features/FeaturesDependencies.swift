// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Dependencies required by the SwiftUI features.
///
/// The App target is the composition root: it creates the concrete
/// implementations and passes them down through this value.
///
/// The required dependencies live on the struct itself; the feature add-ons
/// that previews and tests can omit are grouped in ``OptionalFeatures``. That
/// makes the optional surface explicit instead of spreading seven optionals
/// across the initializer.
@MainActor
public struct FeaturesDependencies {
    /// Features that need an installed site or an on-disk cache.
    ///
    /// Every member is optional because a preview or a test can run without a
    /// network, without an installed adapter or without a persistence store.
    /// Grouping them keeps the required contract visible at the call site.
    @MainActor
    public struct OptionalFeatures {
        public let pageRepository: (any PageRepository)?
        public let readingProgressRepository: (any ReadingProgressRepository)?
        public let bookmarkRepository: (any BookmarkRepository)?
        public let themeDetector: (any SiteThemeDetecting)?
        public let imageLoader: (any ImageLoading)?
        public let adapterStore: (any AdapterStore)?
        public let catalogService: (any SiteCatalogProviding)?
        public let chapterPagesProvider: (any ChapterPagesProviding)?

        /// A set with no optional feature enabled.
        public static let none = OptionalFeatures()

        public init(
            pageRepository: (any PageRepository)? = nil,
            readingProgressRepository: (any ReadingProgressRepository)? = nil,
            bookmarkRepository: (any BookmarkRepository)? = nil,
            themeDetector: (any SiteThemeDetecting)? = nil,
            imageLoader: (any ImageLoading)? = nil,
            adapterStore: (any AdapterStore)? = nil,
            catalogService: (any SiteCatalogProviding)? = nil,
            chapterPagesProvider: (any ChapterPagesProviding)? = nil
        ) {
            self.pageRepository = pageRepository
            self.readingProgressRepository = readingProgressRepository
            self.bookmarkRepository = bookmarkRepository
            self.themeDetector = themeDetector
            self.imageLoader = imageLoader
            self.adapterStore = adapterStore
            self.catalogService = catalogService
            self.chapterPagesProvider = chapterPagesProvider
        }
    }

    // Required: every feature needs the library and the site registry.
    public let mangaRepository: any MangaRepository
    public let chapterRepository: any ChapterRepository
    public let siteProfileRepository: any SiteProfileRepository
    public let themeSource: any ThemeSource

    /// Add-on features. Access them through the properties below.
    public let optional: OptionalFeatures

    public init(
        mangaRepository: any MangaRepository,
        chapterRepository: any ChapterRepository,
        siteProfileRepository: any SiteProfileRepository,
        themeSource: any ThemeSource,
        optional: OptionalFeatures
    ) {
        self.mangaRepository = mangaRepository
        self.chapterRepository = chapterRepository
        self.siteProfileRepository = siteProfileRepository
        self.themeSource = themeSource
        self.optional = optional
    }

    /// Convenience initializer that keeps flat call sites readable.
    public init(
        mangaRepository: any MangaRepository,
        chapterRepository: any ChapterRepository,
        pageRepository: (any PageRepository)? = nil,
        readingProgressRepository: (any ReadingProgressRepository)? = nil,
        bookmarkRepository: (any BookmarkRepository)? = nil,
        siteProfileRepository: any SiteProfileRepository,
        themeSource: any ThemeSource,
        themeDetector: (any SiteThemeDetecting)? = nil,
        imageLoader: (any ImageLoading)? = nil,
        adapterStore: (any AdapterStore)? = nil,
        catalogService: (any SiteCatalogProviding)? = nil,
        chapterPagesProvider: (any ChapterPagesProviding)? = nil
    ) {
        self.init(
            mangaRepository: mangaRepository,
            chapterRepository: chapterRepository,
            siteProfileRepository: siteProfileRepository,
            themeSource: themeSource,
            optional: OptionalFeatures(
                pageRepository: pageRepository,
                readingProgressRepository: readingProgressRepository,
                bookmarkRepository: bookmarkRepository,
                themeDetector: themeDetector,
                imageLoader: imageLoader,
                adapterStore: adapterStore,
                catalogService: catalogService,
                chapterPagesProvider: chapterPagesProvider
            )
        )
    }

    // MARK: - Optional feature accessors

    public var pageRepository: (any PageRepository)? { optional.pageRepository }
    public var readingProgressRepository: (any ReadingProgressRepository)? {
        optional.readingProgressRepository
    }
    public var bookmarkRepository: (any BookmarkRepository)? { optional.bookmarkRepository }
    public var themeDetector: (any SiteThemeDetecting)? { optional.themeDetector }
    public var imageLoader: (any ImageLoading)? { optional.imageLoader }
    public var adapterStore: (any AdapterStore)? { optional.adapterStore }
    public var catalogService: (any SiteCatalogProviding)? { optional.catalogService }
    public var chapterPagesProvider: (any ChapterPagesProviding)? { optional.chapterPagesProvider }
}
