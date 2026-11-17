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
    /// Where this chapter starts when it is opened.
    private let startPosition: ReaderStartPosition
    private var hasLoaded = false
    /// Set once the start position has been applied, so a reload keeps the
    /// page the reader is on instead of jumping back to the entry point.
    private var hasAppliedStartPosition = false

    /// Debounces progress writes triggered by page swipes.
    private var saveDebounceTask: Task<Void, Never>?
    /// Serialises the actual persistence work.
    private var saveChain: Task<Void, Never>?
    private var lastPersistedPageIndex: Int?
    private var lastPersistedTotalPages: Int?
    /// Tracks whether the reader moved within the chapter during this session.
    ///
    /// Opening a chapter and closing it must not record progress: the first
    /// page would otherwise be saved as `1/N` without any reading.
    private var hasNavigatedInSession = false
    private var activeSaveCount = 0

    public init(
        manga: MangaEntity,
        chapter: ChapterEntity,
        pageRepository: any PageRepository,
        readingProgressRepository: any ReadingProgressRepository,
        mangaRepository: any MangaRepository,
        chapterPagesProvider: (any ChapterPagesProviding)? = nil,
        startPosition: ReaderStartPosition = .restore
    ) {
        self.manga = manga
        self.chapter = chapter
        self.pageRepository = pageRepository
        self.readingProgressRepository = readingProgressRepository
        self.mangaRepository = mangaRepository
        self.chapterPagesProvider = chapterPagesProvider
        self.startPosition = startPosition
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
        await loadPages(forceRefresh: false)
    }

    /// Forces a fresh page list, for example after a challenge or an expired
    /// adapter URL made the cached images fail.
    public func reload() async {
        hasLoaded = false
        await loadPages(forceRefresh: true)
    }

    private func loadPages(forceRefresh: Bool) async {
        guard !hasLoaded else { return }

        isLoading = true
        lastError = nil
        defer {
            isLoading = false
        }

        do {
            var loaded = try await pageRepository.fetchByChapterId(chapter.id)
                .sorted { $0.index < $1.index }
            if let chapterPagesProvider, forceRefresh || loaded.isEmpty {
                loaded = try await chapterPagesProvider.pages(
                    for: chapter,
                    manga: manga,
                    forceRefresh: forceRefresh
                ).sorted { $0.index < $1.index }
            }
            pages = loaded
            if hasAppliedStartPosition {
                // A reload must not send the reader back to the entry point.
                currentPageIndex = clampedPageIndex(currentPageIndex)
            } else {
                currentPageIndex = try await initialPageIndex()
                hasAppliedStartPosition = true
            }
            hasLoaded = true
        } catch {
            lastError = error
        }
    }

    /// Page the chapter opens at, honouring the caller's intent.
    private func initialPageIndex() async throws -> Int {
        switch startPosition {
        case .restore:
            return try await restoredPageIndex()
        case .beginning:
            return clampedPageIndex(0)
        case .end:
            return clampedPageIndex(max(totalPages - 1, 0))
        }
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
        hasNavigatedInSession = true
        scheduleProgressSave()
    }

    /// Remembers a page's decoded pixel size so the vertical reader can
    /// reserve the same space when the row is rebuilt.
    ///
    /// `PageEntity` already models the size; without it every revisit starts
    /// from the fallback ratio, the content height changes under the finger
    /// and the scroll view jumps.
    public func recordPageSize(index: Int, width: Int, height: Int) async {
        guard width > 0, height > 0, pages.indices.contains(index) else { return }

        let page = pages[index]
        guard page.width != width || page.height != height else { return }

        page.width = width
        page.height = height
        try? await pageRepository.save(page)
    }

    /// Index of the page that covers the top edge of the viewport.
    ///
    /// `minYs` maps page indices to their top offsets in the scroll view's
    /// coordinate space. A non-positive offset means the row starts above the
    /// viewport, so the greatest such offset is the page being read. Before
    /// the first scroll every row is still below the top edge and the earliest
    /// one wins.
    public nonisolated static func topmostPageIndex(minYs: [Int: Double]) -> Int? {
        if let covering = minYs.filter({ $0.value <= 0 }).max(by: { $0.value < $1.value }) {
            return covering.key
        }
        return minYs.min(by: { $0.value < $1.value })?.key
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

        // Only a real move (or an existing saved position) counts as reading.
        // Re-saving on open would mark an untouched chapter as started.
        guard hasNavigatedInSession || currentPageIndex > 0 || lastPersistedPageIndex != nil else {
            return
        }

        let pageIndex = min(max(currentPageIndex, 0), totalPages - 1)
        if lastPersistedPageIndex == pageIndex, lastPersistedTotalPages == totalPages {
            return
        }

        beginSaving()
        defer { endSaving() }

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

    /// Concurrent saves share one flag: it only clears when the last one ends.
    private func beginSaving() {
        activeSaveCount += 1
        isSavingProgress = true
    }

    private func endSaving() {
        activeSaveCount = max(0, activeSaveCount - 1)
        isSavingProgress = activeSaveCount > 0
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
