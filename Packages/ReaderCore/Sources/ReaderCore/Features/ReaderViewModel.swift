// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// Coordinates page loading and exact resume progress for one chapter.
@MainActor
@Observable
public final class ReaderViewModel {
    public private(set) var pages: [PageEntity] = []
    public private(set) var currentPageIndex = 0
    public private(set) var isLoading = false
    public private(set) var isSavingProgress = false
    public var lastError: Error?

    public let manga: MangaEntity
    public let chapter: ChapterEntity

    private let pageRepository: any PageRepository
    private let readingProgressRepository: any ReadingProgressRepository
    private let mangaRepository: any MangaRepository
    private let chapterPagesProvider: (any ChapterPagesProviding)?
    private var hasLoaded = false

    /// Debounces progress writes triggered by page swipes.
    private var saveDebounceTask: Task<Void, Never>?
    /// Serialises the actual persistence work.
    private var saveChain: Task<Void, Never>?
    private var lastPersistedPageIndex: Int?
    private var lastPersistedTotalPages: Int?

    public init(
        manga: MangaEntity,
        chapter: ChapterEntity,
        pageRepository: any PageRepository,
        readingProgressRepository: any ReadingProgressRepository,
        mangaRepository: any MangaRepository,
        chapterPagesProvider: (any ChapterPagesProviding)? = nil
    ) {
        self.manga = manga
        self.chapter = chapter
        self.pageRepository = pageRepository
        self.readingProgressRepository = readingProgressRepository
        self.mangaRepository = mangaRepository
        self.chapterPagesProvider = chapterPagesProvider
    }

    public var totalPages: Int {
        pages.count > 0 ? pages.count : chapter.pageCount
    }

    public var progress: Double {
        guard totalPages > 0 else { return 0 }
        return Double(min(currentPageIndex + 1, totalPages)) / Double(totalPages)
    }

    public var pageNumber: Int {
        guard totalPages > 0 else { return 0 }
        return min(currentPageIndex + 1, totalPages)
    }

    public func load() async {
        guard !hasLoaded else { return }

        isLoading = true
        lastError = nil
        defer {
            isLoading = false
        }

        do {
            var loaded = try await pageRepository.fetchByChapterId(chapter.id).sorted { $0.index < $1.index }
            if loaded.isEmpty, let chapterPagesProvider {
                loaded = try await chapterPagesProvider.pages(for: chapter, manga: manga)
                    .sorted { $0.index < $1.index }
            }
            pages = loaded
            currentPageIndex = try await restoredPageIndex()
            hasLoaded = true
        } catch {
            lastError = error
        }
    }

    /// Forces a reload, for example after the user completes a site challenge.
    public func reload() async {
        hasLoaded = false
        await load()
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

    public func setPage(index: Int) async {
        guard totalPages > 0 else { return }
        let clampedIndex = min(max(index, 0), totalPages - 1)
        guard clampedIndex != currentPageIndex else { return }
        currentPageIndex = clampedIndex
        scheduleProgressSave()
    }

    /// Schedules a debounced progress write for rapid page changes.
    private func scheduleProgressSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.saveProgress()
        }
    }

    /// Cancels the debounce and persists the current position immediately.
    public func flushProgress() async {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        await saveProgress()
    }

    public func saveProgress() async {
        guard totalPages > 0 else { return }

        // Chain saves so two rapid writes cannot interleave on the same entry.
        let previous = saveChain
        let task = Task { [weak self] in
            await previous?.value
            await self?.persistProgress()
        }
        saveChain = task
        await task.value
    }

    private func persistProgress() async {
        guard totalPages > 0 else { return }

        let pageIndex = min(max(currentPageIndex, 0), totalPages - 1)
        if lastPersistedPageIndex == pageIndex, lastPersistedTotalPages == totalPages {
            return
        }

        isSavingProgress = true
        defer { isSavingProgress = false }

        do {
            let progressEntries = try await readingProgressRepository.fetchByMangaIdAndChapterId(
                manga.id,
                chapterId: chapter.id
            )

            let entry =
                progressEntries.max { $0.readAt < $1.readAt }
                ?? ReadingProgressEntity(
                    id: Self.progressID(mangaID: manga.id, chapterID: chapter.id),
                    pageIndex: pageIndex,
                    totalPages: totalPages,
                    manga: manga,
                    chapter: chapter
                )
            entry.pageIndex = pageIndex
            entry.totalPages = totalPages
            entry.progress = progress
            entry.readAt = Date()
            entry.manga = manga
            entry.chapter = chapter
            try await readingProgressRepository.save(entry)

            manga.updateReadingPosition(
                chapterId: chapter.id,
                pageIndex: pageIndex,
                totalPages: totalPages
            )
            try await mangaRepository.save(manga)

            lastPersistedPageIndex = pageIndex
            lastPersistedTotalPages = totalPages
        } catch {
            lastError = error
        }
    }

    public static func progressID(mangaID: String, chapterID: String) -> String {
        "\(mangaID)::\(chapterID)"
    }

    private func restoredPageIndex() async throws -> Int {
        if let progress =
            try await readingProgressRepository
            .fetchByMangaIdAndChapterId(manga.id, chapterId: chapter.id)
            .max(by: { $0.readAt < $1.readAt })
        {
            return clampedPageIndex(progress.pageIndex)
        }

        if let relationshipProgress = chapter.readingProgressEntries.max(by: { $0.readAt < $1.readAt }) {
            return clampedPageIndex(relationshipProgress.pageIndex)
        }

        guard manga.lastReadChapterId == chapter.id, let pageIndex = manga.lastReadPageIndex else {
            return 0
        }
        return clampedPageIndex(pageIndex)
    }

    private func clampedPageIndex(_ index: Int) -> Int {
        guard totalPages > 0 else { return 0 }
        return min(max(index, 0), totalPages - 1)
    }
}
