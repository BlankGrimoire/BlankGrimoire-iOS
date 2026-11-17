// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// Coordinates page loading and exact resume progress for one chapter.
@MainActor
@Observable
public final class ReaderViewModel {
    public private(set) var pages: [PageEntity] = []
    public private(set) var currentPageIndex = 0
    /// How far the reader scrolled into `currentPageIndex`, from 0 to 1.
    ///
    /// Only meaningful in vertical mode: a page taller than the screen holds
    /// several screenfuls, and the index alone would restore its top.
    public private(set) var currentPageOffset: Double = 0
    public private(set) var isLoading = false
    public private(set) var isSavingProgress = false
    public var lastError: Error?

    public let manga: MangaEntity
    public let chapter: ChapterEntity

    private let pageRepository: any PageRepository
    private let readingProgressRepository: any ReadingProgressRepository
    private let mangaRepository: any MangaRepository
    private let chapterPagesProvider: (any ChapterPagesProviding)?
    /// Where the reader stopped inside the page, kept outside SwiftData.
    private let positionStore: ReadingPositionStore
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
    private var lastPersistedPageOffset: Double?
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
        startPosition: ReaderStartPosition = .restore,
        positionStore: ReadingPositionStore = ReadingPositionStore()
    ) {
        self.manga = manga
        self.chapter = chapter
        self.pageRepository = pageRepository
        self.readingProgressRepository = readingProgressRepository
        self.mangaRepository = mangaRepository
        self.chapterPagesProvider = chapterPagesProvider
        self.startPosition = startPosition
        self.positionStore = positionStore
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
                let position = try await initialPosition()
                currentPageIndex = position.index
                currentPageOffset = position.fraction
                hasAppliedStartPosition = true
            }
            hasLoaded = true
        } catch {
            lastError = error
        }
    }

    /// Page and in-page offset the chapter opens at, honouring the caller's
    /// intent.
    private func initialPosition() async throws -> (index: Int, fraction: Double) {
        switch startPosition {
        case .restore:
            return try await restoredPosition()
        case .beginning:
            return (clampedPageIndex(0), 0)
        case .end:
            return (clampedPageIndex(max(totalPages - 1, 0)), 0)
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
        guard clampedIndex != currentPageIndex || currentPageOffset != 0 else { return }
        currentPageIndex = clampedIndex
        // Horizontal paging shows whole pages, so there is no offset to keep.
        currentPageOffset = 0
        hasNavigatedInSession = true
        scheduleProgressSave()
    }

    /// Records the scroll position inside the current page.
    ///
    /// The vertical reader reports it on every layout change, so the debounce
    /// keeps writes to one per scroll burst.
    public func setPosition(index: Int, fraction: Double) async {
        guard totalPages > 0 else { return }

        let clampedIndex = min(max(index, 0), totalPages - 1)
        let clampedFraction = min(max(fraction, 0), 1)
        let indexChanged = clampedIndex != currentPageIndex
        let fractionChanged = abs(clampedFraction - currentPageOffset) > 0.001
        guard indexChanged || fractionChanged else { return }

        currentPageIndex = clampedIndex
        currentPageOffset = clampedFraction
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
    ///
    /// `tolerance` absorbs the fractional offsets SwiftUI reports at the end
    /// of a scrolled list, where a row can sit a hair below the top edge.
    public nonisolated static func topmostPageIndex(minYs: [Int: Double], tolerance: Double = 1) -> Int? {
        if let covering = minYs.filter({ $0.value <= tolerance }).max(by: { $0.value < $1.value }) {
            return covering.key
        }
        return minYs.min(by: { $0.value < $1.value })?.key
    }

    /// Page considered current for a given scroll position.
    ///
    /// Page images do not share a ratio: a short last image may never reach
    /// the top edge, so the chapter would never look finished. Once the last
    /// page is fully visible the reader is at the end of the chapter, and the
    /// last page becomes current regardless of which row covers the top.
    public nonisolated static func currentPageIndex(
        minYs: [Int: Double],
        lastPageIndex: Int,
        lastPageBottom: Double?,
        viewportHeight: Double,
        tolerance: Double = 1
    ) -> Int? {
        guard !minYs.isEmpty else { return nil }

        if minYs[lastPageIndex] != nil, let lastPageBottom,
            lastPageBottom <= viewportHeight + tolerance
        {
            return lastPageIndex
        }

        return topmostPageIndex(minYs: minYs, tolerance: tolerance)
    }

    /// Anchor in `0...1` that lands on `fraction` of a page.
    ///
    /// `scrollTo(anchor:)` aligns the same fractional point of the row and of
    /// the viewport, which shifts the content by `anchor * (pageHeight -
    /// viewport)`. A page that fits on screen cannot shift at all, and an
    /// anchor of 1 already reaches its bottom.
    public nonisolated static func scrollAnchor(
        for fraction: Double,
        pageHeight: Double,
        viewport: Double
    ) -> Double {
        guard fraction > 0, pageHeight > viewport, viewport > 0 else { return 0 }
        return min(1, fraction * pageHeight / (pageHeight - viewport))
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
        let pageOffset = min(max(currentPageOffset, 0), 1)
        if lastPersistedPageIndex == pageIndex, lastPersistedTotalPages == totalPages,
            let persisted = lastPersistedPageOffset,
            abs(persisted - pageOffset) <= 0.001
        {
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

            positionStore.setPosition(
                pageIndex: pageIndex,
                offset: pageOffset,
                mangaID: manga.id,
                chapterID: chapter.id
            )

            manga.updateReadingPosition(
                chapterId: chapter.id,
                pageIndex: pageIndex,
                totalPages: totalPages
            )
            try await mangaRepository.save(manga)

            lastPersistedPageIndex = pageIndex
            lastPersistedTotalPages = totalPages
            lastPersistedPageOffset = pageOffset
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

    /// Saved page and in-page offset for this chapter.
    ///
    /// The page comes from the stored progress; the offset only applies when
    /// it belongs to the same page, so a position left on an older page
    /// cannot drag the reader deeper into a different one.
    private func restoredPosition() async throws -> (index: Int, fraction: Double) {
        if let progress =
            try await readingProgressRepository
            .fetchByMangaIdAndChapterId(manga.id, chapterId: chapter.id)
            .max(by: { $0.readAt < $1.readAt })
        {
            return position(pageIndex: progress.pageIndex)
        }

        if let relationshipProgress = chapter.readingProgressEntries.max(by: { $0.readAt < $1.readAt }) {
            return position(pageIndex: relationshipProgress.pageIndex)
        }

        guard manga.lastReadChapterId == chapter.id, let pageIndex = manga.lastReadPageIndex else {
            return (0, 0)
        }
        return (clampedPageIndex(pageIndex), 0)
    }

    private func position(pageIndex: Int) -> (index: Int, fraction: Double) {
        let index = clampedPageIndex(pageIndex)
        guard let saved = positionStore.position(mangaID: manga.id, chapterID: chapter.id),
            saved.pageIndex == index
        else {
            return (index, 0)
        }
        return (index, clampedPageOffset(saved.offset))
    }

    private func clampedPageIndex(_ index: Int) -> Int {
        guard totalPages > 0 else { return 0 }
        return min(max(index, 0), totalPages - 1)
    }

    private func clampedPageOffset(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }
}
