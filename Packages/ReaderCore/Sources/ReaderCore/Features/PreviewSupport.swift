// SPDX-License-Identifier: MPL-2.0

#if DEBUG
    import Foundation

    // MARK: - Synthetic Preview Data

    extension MangaEntity {
        static var previewData: [MangaEntity] {
            let first = MangaEntity(
                id: "preview-1",
                title: "Lorem Ipsum",
                coverURL: "https://example.org/covers/lorem.jpg",
                authors: ["Lorem Author"],
                tags: ["adventure", "fantasy"],
                status: .ongoing,
                isFavorite: true,
                siteProfileID: "preview-site-1",
                siteName: "Example Site",
                siteURL: "https://example.org"
            )
            first.readingProgress = 0.65
            first.lastReadChapterId = "chapter-3"
            first.lastReadAt = Date().addingTimeInterval(-86_400)

            let second = MangaEntity(
                id: "preview-2",
                title: "Dolor Sit Amet",
                coverURL: "https://example.org/covers/dolor.jpg",
                authors: ["Ipsum Author"],
                tags: ["action", "drama"],
                status: .completed,
                isFavorite: true,
                siteProfileID: "preview-site-1",
                siteName: "Example Site",
                siteURL: "https://example.org"
            )
            second.readingProgress = 1.0
            second.lastReadChapterId = "chapter-2"
            second.lastReadAt = Date().addingTimeInterval(-172_800)

            let third = MangaEntity(
                id: "preview-3",
                title: "Consectetur Adipiscing",
                coverURL: "https://example.org/covers/consectetur.jpg",
                authors: ["Dolor Author"],
                tags: ["mystery", "fantasy"],
                status: .ongoing,
                siteProfileID: "preview-site-2",
                siteName: "Sample Site",
                siteURL: "https://example.com"
            )
            third.readingProgress = 0.3
            third.lastReadAt = Date().addingTimeInterval(-3_600)

            let fourth = MangaEntity(
                id: "preview-4",
                title: "Sed Do Eiusmod",
                coverURL: "https://example.org/covers/sed.jpg",
                authors: ["Amet Author"],
                tags: ["action", "adventure"],
                status: .ongoing,
                siteProfileID: "preview-site-2",
                siteName: "Sample Site",
                siteURL: "https://example.com"
            )

            return [first, second, third, fourth]
        }
    }

    extension ChapterEntity {
        static var previewData: [ChapterEntity] {
            let chapters = (1...5).map { index in
                ChapterEntity(
                    id: "preview-chapter-\(index)",
                    title: "Chapter \(index): Lorem Ipsum",
                    number: Double(index),
                    volume: 1,
                    language: "en",
                    publishedAt: Date().addingTimeInterval(-86_400 * Double(6 - index)),
                    pageCount: 18
                )
            }
            chapters.first?.isDownloaded = true
            return chapters
        }
    }

    extension SiteProfile {
        static var previewData: [SiteProfile] {
            [
                SiteProfile(
                    id: "preview-site-1",
                    name: "Example Site",
                    baseURL: "https://example.org",
                    themeID: "theme.example",
                    themeVersion: "1.0.0"
                ),
                SiteProfile(
                    id: "preview-site-2",
                    name: "Sample Site",
                    baseURL: "https://example.com",
                    themeID: "theme.sample",
                    themeVersion: "1.0.0",
                    selectorOverrides: ThemeSelectorsOverrides(
                        search: .init(path: "/search"),
                        details: .init(title: ".title")
                    )
                ),
            ]
        }
    }

    extension ThemeAdapter {
        static var previewData: [ThemeAdapter] {
            [
                ThemeAdapter(
                    id: "theme.example",
                    name: "Example Theme",
                    version: "1.0.0",
                    detectionSignature: ThemeSignature(minScore: 10),
                    selectors: ThemeSelectors(
                        search: .init(path: "/search", item: ".card", title: ".title", link: "a", cover: "img"),
                        details: .init(title: ".title", cover: ".cover img", synopsis: ".description"),
                        chapters: .init(
                            item: ".chapter-row",
                            link: "a",
                            title: ".chapter-title",
                            date: ".date",
                            order: "desc"
                        ),
                        pages: .init(strategies: [
                            .css(CSSStrategy(image: ".reader img", srcAttributes: ["data-src"]))
                        ]),
                        attribution: .init(logo: ".logo img", credits: ".credits")
                    )
                ),
                ThemeAdapter(
                    id: "theme.sample",
                    name: "Sample Theme",
                    version: "1.0.0",
                    detectionSignature: ThemeSignature(minScore: 10),
                    selectors: ThemeSelectors(
                        search: .init(path: "/search", item: ".item", title: ".title", link: "a", cover: "img"),
                        details: .init(title: ".title", cover: ".cover img", synopsis: ".synopsis"),
                        chapters: .init(
                            item: ".chapter-item",
                            link: "a",
                            title: ".chapter-title",
                            date: ".date",
                            order: "desc"
                        ),
                        pages: .init(strategies: [
                            .css(CSSStrategy(image: ".page img", srcAttributes: ["src"]))
                        ]),
                        attribution: .init(logo: ".logo img", credits: ".credits")
                    )
                ),
            ]
        }
    }

    // MARK: - Preview Repositories

    @MainActor
    final class PreviewMangaRepository: MangaRepository {
        func fetchAll() async throws -> [MangaEntity] { MangaEntity.previewData }
        func fetchById(_ id: String) async throws -> MangaEntity? { nil }
        func fetchByIds(_ ids: [String]) async throws -> [MangaEntity] { [] }
        func fetchFavorites() async throws -> [MangaEntity] { [] }
        func fetchRecent(limit: Int) async throws -> [MangaEntity] { [] }
        func fetchByStatus(_ status: MangaStatus) async throws -> [MangaEntity] { [] }
        func fetchByTag(_ tag: String) async throws -> [MangaEntity] { [] }
        func search(query: String) async throws -> [MangaEntity] { [] }
        func save(_ manga: MangaEntity) async throws {}
        func delete(_ manga: MangaEntity) async throws {}
        func deleteAll() async throws {}
        func count() async throws -> Int { 0 }
    }

    @MainActor
    final class PreviewChapterRepository: ChapterRepository {
        func fetchByMangaId(_ mangaId: String) async throws -> [ChapterEntity] { ChapterEntity.previewData }
        func fetchById(_ id: String) async throws -> ChapterEntity? { nil }
        func fetchByMangaIdAndNumber(_ mangaId: String, number: Double) async throws -> ChapterEntity? { nil }
        func fetchByIds(_ ids: [String]) async throws -> [ChapterEntity] { [] }
        func fetchDownloadedChapters(for mangaId: String) async throws -> [ChapterEntity] { [] }
        func save(_ chapter: ChapterEntity) async throws {}
        func saveAll(_ chapters: [ChapterEntity]) async throws {}
        func delete(_ chapter: ChapterEntity) async throws {}
        func deleteAll(for mangaId: String) async throws {}
        func updateDownloadStatus(
            _ chapterId: String,
            isDownloaded: Bool,
            downloadedPagesCount: Int
        ) async throws {}
    }

    @MainActor
    final class PreviewSiteProfileRepository: SiteProfileRepository {
        func fetchAll() async throws -> [SiteProfile] { SiteProfile.previewData }
        func fetch(id: String) async throws -> SiteProfile? { nil }
        func fetchByBaseURL(_ baseURL: String) async throws -> SiteProfile? { nil }
        func save(_ profile: SiteProfile) async throws {}
        func delete(_ profile: SiteProfile) async throws {}
    }

    @MainActor
    final class PreviewPageRepository: PageRepository {
        func fetchByChapterId(_ chapterId: String) async throws -> [PageEntity] {
            (0..<3).map { index in
                PageEntity(
                    index: index,
                    imageURL: "https://example.org/pages/lorem-\(index + 1).jpg"
                )
            }
        }
        func fetchById(_ id: String) async throws -> PageEntity? { nil }
        func fetchByChapterIdAndIndex(_ chapterId: String, index: Int) async throws -> PageEntity? { nil }
        func save(_ page: PageEntity) async throws {}
        func saveAll(_ pages: [PageEntity]) async throws {}
        func delete(_ page: PageEntity) async throws {}
        func deleteAll(for chapterId: String) async throws {}
        func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws {}
    }

    @MainActor
    final class PreviewReadingProgressRepository: ReadingProgressRepository {
        func fetchByMangaId(_ mangaId: String) async throws -> [ReadingProgressEntity] { [] }
        func fetchByMangaIdAndChapterId(_ mangaId: String, chapterId: String) async throws
            -> [ReadingProgressEntity]
        { [] }
        func fetchLatest(for mangaId: String) async throws -> ReadingProgressEntity? { nil }
        func save(_ progress: ReadingProgressEntity) async throws {}
        func delete(_ progress: ReadingProgressEntity) async throws {}
        func deleteAll(for mangaId: String) async throws {}
    }

    @MainActor
    final class PreviewCatalogService: SiteCatalogProviding {
        func search(query: String, in profiles: [SiteProfile]) async -> SiteSearchOutcome {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return SiteSearchOutcome()
            }
            let results = profiles.map { profile in
                SiteSearchResult(
                    siteProfileID: profile.id,
                    siteName: profile.name,
                    siteURL: profile.baseURL,
                    key: "\(profile.baseURL)/series/lorem-ipsum",
                    title: "Lorem Ipsum",
                    coverURL: "https://example.org/covers/lorem.jpg"
                )
            }
            return SiteSearchOutcome(results: results)
        }

        func importManga(_ result: SiteSearchResult) async throws -> MangaEntity {
            MangaEntity(
                id: result.key,
                title: result.title,
                coverURL: result.coverURL,
                siteProfileID: result.siteProfileID,
                siteName: result.siteName,
                siteURL: result.siteURL
            )
        }

        func refreshChapters(for manga: MangaEntity) async throws {}
    }

    @MainActor
    final class PreviewChapterPagesProvider: ChapterPagesProviding {
        func pages(for chapter: ChapterEntity, manga: MangaEntity) async throws -> [PageEntity] {
            (0..<3).map { index in
                PageEntity(index: index, imageURL: "https://example.org/pages/lorem-\(index + 1).jpg")
            }
        }
    }

    struct PreviewThemeSource: ThemeSource {
        func listThemes() async throws -> [ThemeAdapter] { ThemeAdapter.previewData }
        func getTheme(id: String) async throws -> ThemeAdapter? { nil }
        func hasTheme(id: String) async throws -> Bool { false }
    }

    struct PreviewSiteThemeDetector: SiteThemeDetecting {
        func detectTheme(for url: String) async throws -> ThemeDetectionResult {
            ThemeDetectionResult(
                theme: ThemeAdapter.previewData[0],
                score: 10,
                matchedSignals: ["preview"]
            )
        }
    }

    @MainActor
    extension FeaturesDependencies {
        public static var preview: FeaturesDependencies {
            FeaturesDependencies(
                mangaRepository: PreviewMangaRepository(),
                chapterRepository: PreviewChapterRepository(),
                pageRepository: PreviewPageRepository(),
                readingProgressRepository: PreviewReadingProgressRepository(),
                siteProfileRepository: PreviewSiteProfileRepository(),
                themeSource: PreviewThemeSource(),
                themeDetector: PreviewSiteThemeDetector(),
                catalogService: PreviewCatalogService(),
                chapterPagesProvider: PreviewChapterPagesProvider()
            )
        }
    }
#endif
