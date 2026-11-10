// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Dependencies required by the SwiftUI features.
///
/// The App target is the composition root: it creates the concrete
/// implementations and passes them down through this value.
@MainActor
public struct FeaturesDependencies {
    public let mangaRepository: any MangaRepository
    public let chapterRepository: any ChapterRepository
    public let pageRepository: (any PageRepository)?
    public let readingProgressRepository: (any ReadingProgressRepository)?
    public let bookmarkRepository: (any BookmarkRepository)?
    public let siteProfileRepository: any SiteProfileRepository
    public let themeSource: any ThemeSource
    public let themeDetector: (any SiteThemeDetecting)?
    public let imageLoader: (any ImageLoading)?
    public let adapterStore: (any AdapterStore)?
    public let catalogService: (any SiteCatalogProviding)?
    public let chapterPagesProvider: (any ChapterPagesProviding)?

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
        self.mangaRepository = mangaRepository
        self.chapterRepository = chapterRepository
        self.pageRepository = pageRepository
        self.readingProgressRepository = readingProgressRepository
        self.bookmarkRepository = bookmarkRepository
        self.siteProfileRepository = siteProfileRepository
        self.themeSource = themeSource
        self.themeDetector = themeDetector
        self.imageLoader = imageLoader
        self.adapterStore = adapterStore
        self.catalogService = catalogService
        self.chapterPagesProvider = chapterPagesProvider
    }
}
