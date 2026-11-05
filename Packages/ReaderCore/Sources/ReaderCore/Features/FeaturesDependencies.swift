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
    public let siteProfileRepository: any SiteProfileRepository
    public let themeSource: any ThemeSource
    public let themeDetector: (any SiteThemeDetecting)?
    public let imageLoader: (any ImageLoading)?

    public init(
        mangaRepository: any MangaRepository,
        chapterRepository: any ChapterRepository,
        siteProfileRepository: any SiteProfileRepository,
        themeSource: any ThemeSource,
        themeDetector: (any SiteThemeDetecting)? = nil,
        imageLoader: (any ImageLoading)? = nil
    ) {
        self.mangaRepository = mangaRepository
        self.chapterRepository = chapterRepository
        self.siteProfileRepository = siteProfileRepository
        self.themeSource = themeSource
        self.themeDetector = themeDetector
        self.imageLoader = imageLoader
    }
}
