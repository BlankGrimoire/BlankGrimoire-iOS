// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// View model for manga detail view
@MainActor
@Observable
public final class MangaDetailViewModel {
    public var chapters: [ChapterEntity] = []
    public var isLoadingChapters: Bool = false
    public var lastError: Error?

    private let manga: MangaEntity
    private let chapterRepository: any ChapterRepository
    private let mangaRepository: any MangaRepository
    private let catalogService: (any SiteCatalogProviding)?

    public init(
        manga: MangaEntity,
        chapterRepository: any ChapterRepository,
        mangaRepository: any MangaRepository,
        catalogService: (any SiteCatalogProviding)? = nil
    ) {
        self.manga = manga
        self.chapterRepository = chapterRepository
        self.mangaRepository = mangaRepository
        self.catalogService = catalogService
    }

    public func loadChapters() async {
        isLoadingChapters = true
        lastError = nil
        defer { isLoadingChapters = false }

        do {
            chapters = Self.sortedChapters(try await chapterRepository.fetchByMangaId(manga.id))
        } catch {
            lastError = error
        }
    }

    /// Refreshes the series from its site, falling back to the local chapters.
    ///
    /// A network failure is surfaced as an error but must not empty the
    /// already imported chapter list.
    public func refresh() async {
        if let catalogService {
            isLoadingChapters = true
            lastError = nil
            do {
                try await catalogService.refreshChapters(for: manga)
            } catch {
                lastError = error
            }
        }

        do {
            chapters = Self.sortedChapters(try await chapterRepository.fetchByMangaId(manga.id))
        } catch {
            lastError = error
        }
        isLoadingChapters = false
    }

    /// URL the visible verification browser must open, when the site asked for
    /// a challenge.
    public var challengeURL: URL? {
        guard let error = lastError as? SiteBrowsingError else { return nil }
        if case .challengeRequired(let url) = error {
            return url
        }
        return nil
    }

    public func toggleFavorite() async {
        let previousValue = manga.isFavorite
        manga.isFavorite.toggle()

        do {
            try await mangaRepository.save(manga)
        } catch {
            manga.isFavorite = previousValue
            lastError = error
        }
    }

    public func readChapter(_ chapter: ChapterEntity) async {
        let target = chapter.manga ?? manga
        let totalPages = max(chapter.pageCount, 1)
        target.updateLastRead(
            chapterId: chapter.id,
            pageIndex: 0,
            totalPages: totalPages
        )

        do {
            try await mangaRepository.save(target)
        } catch {
            lastError = error
        }
    }

    /// Marks every chapter as read by moving the series position to the end of
    /// the last chapter in reading order.
    public func markAllAsRead() async {
        if chapters.isEmpty {
            await loadChapters()
        }

        guard let lastChapter = Self.sortedChapters(chapters).last else {
            return
        }

        let totalPages = max(lastChapter.pageCount, 1)
        manga.updateLastRead(
            chapterId: lastChapter.id,
            pageIndex: totalPages - 1,
            totalPages: totalPages
        )

        do {
            try await mangaRepository.save(manga)
        } catch {
            lastError = error
        }
    }

    /// Deletes the manga from the local library.
    ///
    /// - Returns: `true` when the deletion succeeded.
    public func deleteManga() async -> Bool {
        do {
            try await mangaRepository.delete(manga)
            return true
        } catch {
            lastError = error
            return false
        }
    }

    /// Sorts chapters by numeric order, with unnumbered chapters last.
    private static func sortedChapters(_ chapters: [ChapterEntity]) -> [ChapterEntity] {
        chapters.sorted { lhs, rhs in
            let left = lhs.number ?? .greatestFiniteMagnitude
            let right = rhs.number ?? .greatestFiniteMagnitude
            if left != right {
                return left < right
            }
            return lhs.id < rhs.id
        }
    }
}
