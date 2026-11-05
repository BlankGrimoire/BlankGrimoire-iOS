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

    public init(
        manga: MangaEntity,
        chapterRepository: any ChapterRepository,
        mangaRepository: any MangaRepository
    ) {
        self.manga = manga
        self.chapterRepository = chapterRepository
        self.mangaRepository = mangaRepository
    }

    public func loadChapters() async {
        isLoadingChapters = true
        lastError = nil
        defer { isLoadingChapters = false }

        do {
            chapters = try await chapterRepository.fetchByMangaId(manga.id)
        } catch {
            lastError = error
        }
    }

    public func refresh() async {
        await loadChapters()
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
        target.updateLastRead(
            chapterId: chapter.id,
            pageIndex: 0,
            totalPages: chapter.pageCount
        )

        do {
            try await mangaRepository.save(target)
        } catch {
            lastError = error
        }
    }

    public func markAllAsRead() async {
        guard
            let lastChapter = chapters.max(by: {
                ($0.number ?? 0) < ($1.number ?? 0)
            })
        else {
            return
        }

        manga.updateLastRead(
            chapterId: lastChapter.id,
            pageIndex: lastChapter.pageCount,
            totalPages: lastChapter.pageCount
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
}
