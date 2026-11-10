// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

// MARK: - SwiftData Repository Implementation

/// Inserts a model only when it is not already attached to a context.
///
/// `ModelContext.insert` is not an upsert: calling it for an object that was
/// fetched from the same context can create duplicate rows when the model's
/// unique attribute is not enforced by the store.
@MainActor
private func insertIfNeeded<T: PersistentModel>(_ model: T, into context: ModelContext) {
    if model.modelContext == nil {
        context.insert(model)
    }
}

/// Removes a downloaded page file.
///
/// Only paths inside the app's own container are deleted: `localPath` comes
/// from persisted data and must never be able to delete arbitrary files.
@MainActor
private func removeDownloadedFile(at path: String?) {
    guard let path, !path.isEmpty else { return }
    let url = URL(fileURLWithPath: path).standardizedFileURL

    let fileManager = FileManager.default
    let roots = [
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
    ].compactMap { $0?.standardizedFileURL.path }

    guard roots.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else {
        return
    }
    try? fileManager.removeItem(at: url)
}

@MainActor
final class SwiftDataMangaRepository: MangaRepository {
    private let coordinator: PersistenceCoordinator

    private var context: ModelContext { coordinator.context }

    init(coordinator: PersistenceCoordinator) {
        self.coordinator = coordinator
    }

    func fetchAll() async throws -> [MangaEntity] {
        let descriptor = FetchDescriptor<MangaEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchById(_ id: String) async throws -> MangaEntity? {
        let descriptor = FetchDescriptor<MangaEntity>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func fetchByIds(_ ids: [String]) async throws -> [MangaEntity] {
        let descriptor = FetchDescriptor<MangaEntity>(predicate: #Predicate { ids.contains($0.id) })
        return try context.fetch(descriptor)
    }

    func fetchFavorites() async throws -> [MangaEntity] {
        let descriptor = FetchDescriptor<MangaEntity>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchRecent(limit: Int) async throws -> [MangaEntity] {
        var descriptor = FetchDescriptor<MangaEntity>(
            sortBy: [SortDescriptor(\.lastReadAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func fetchByStatus(_ status: MangaStatus) async throws -> [MangaEntity] {
        // Older SwiftData versions cannot capture enum values in #Predicate.
        // Filtering in memory keeps this working across toolchains.
        let all = try await fetchAll()
        return all.filter { $0.status == status }
    }

    func fetchByTag(_ tag: String) async throws -> [MangaEntity] {
        let all = try await fetchAll()
        return all.filter { $0.tags.contains(tag) }
    }

    func search(query: String) async throws -> [MangaEntity] {
        let all = try await fetchAll()
        return all.filter { manga in
            manga.title.localizedStandardContains(query)
                || manga.authors.contains { $0.localizedStandardContains(query) }
                || manga.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    func save(_ manga: MangaEntity) async throws {
        manga.updatedAt = Date()
        insertIfNeeded(manga, into: context)
        try coordinator.save()
    }

    func delete(_ manga: MangaEntity) async throws {
        context.delete(manga)
        try coordinator.save()
    }

    func deleteAll() async throws {
        let all = try await fetchAll()
        for manga in all {
            context.delete(manga)
        }
        try coordinator.save()
    }

    func count() async throws -> Int {
        let descriptor = FetchDescriptor<MangaEntity>()
        return try context.fetchCount(descriptor)
    }
}

@MainActor
final class SwiftDataChapterRepository: ChapterRepository {
    private let coordinator: PersistenceCoordinator

    private var context: ModelContext { coordinator.context }

    init(coordinator: PersistenceCoordinator) {
        self.coordinator = coordinator
    }

    func fetchByMangaId(_ mangaId: String) async throws -> [ChapterEntity] {
        let descriptor = FetchDescriptor<ChapterEntity>(
            predicate: #Predicate { $0.manga?.id == mangaId },
            sortBy: [SortDescriptor(\.number, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchById(_ id: String) async throws -> ChapterEntity? {
        let descriptor = FetchDescriptor<ChapterEntity>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func fetchByMangaIdAndNumber(_ mangaId: String, number: Double) async throws -> ChapterEntity? {
        let descriptor = FetchDescriptor<ChapterEntity>(
            predicate: #Predicate { $0.manga?.id == mangaId && $0.number == number }
        )
        return try context.fetch(descriptor).first
    }

    func fetchByIds(_ ids: [String]) async throws -> [ChapterEntity] {
        let descriptor = FetchDescriptor<ChapterEntity>(predicate: #Predicate { ids.contains($0.id) })
        return try context.fetch(descriptor)
    }

    func fetchDownloadedChapters(for mangaId: String) async throws -> [ChapterEntity] {
        let descriptor = FetchDescriptor<ChapterEntity>(
            predicate: #Predicate { $0.manga?.id == mangaId && $0.isDownloaded == true },
            sortBy: [SortDescriptor(\.number, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func save(_ chapter: ChapterEntity) async throws {
        chapter.updatedAt = Date()
        insertIfNeeded(chapter, into: context)
        try coordinator.save()
    }

    func saveAll(_ chapters: [ChapterEntity]) async throws {
        for chapter in chapters {
            chapter.updatedAt = Date()
            insertIfNeeded(chapter, into: context)
        }
        try coordinator.save()
    }

    func delete(_ chapter: ChapterEntity) async throws {
        try deletePages(for: chapter)
        context.delete(chapter)
        try coordinator.save()
    }

    func deleteAll(for mangaId: String) async throws {
        let chapters = try await fetchByMangaId(mangaId)
        for chapter in chapters {
            try deletePages(for: chapter)
            context.delete(chapter)
        }
        try coordinator.save()
    }

    /// Deletes a chapter's pages and their downloaded files.
    private func deletePages(for chapter: ChapterEntity) throws {
        let chapterID = chapter.id
        let descriptor = FetchDescriptor<PageEntity>(
            predicate: #Predicate { $0.chapter?.id == chapterID }
        )
        for page in try context.fetch(descriptor) {
            removeDownloadedFile(at: page.localPath)
            context.delete(page)
        }
    }

    func updateDownloadStatus(_ chapterId: String, isDownloaded: Bool, downloadedPagesCount: Int) async throws {
        guard let chapter = try await fetchById(chapterId) else { return }
        chapter.isDownloaded = isDownloaded
        chapter.downloadedPagesCount = downloadedPagesCount
        chapter.downloadedAt = isDownloaded ? Date() : nil
        chapter.updatedAt = Date()
        try coordinator.save()
    }
}

@MainActor
final class SwiftDataPageRepository: PageRepository {
    private let coordinator: PersistenceCoordinator

    private var context: ModelContext { coordinator.context }

    init(coordinator: PersistenceCoordinator) {
        self.coordinator = coordinator
    }

    func fetchByChapterId(_ chapterId: String) async throws -> [PageEntity] {
        let descriptor = FetchDescriptor<PageEntity>(
            predicate: #Predicate { $0.chapter?.id == chapterId },
            sortBy: [SortDescriptor(\.index, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchById(_ id: String) async throws -> PageEntity? {
        let descriptor = FetchDescriptor<PageEntity>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func fetchByChapterIdAndIndex(_ chapterId: String, index: Int) async throws -> PageEntity? {
        let descriptor = FetchDescriptor<PageEntity>(
            predicate: #Predicate { $0.chapter?.id == chapterId && $0.index == index }
        )
        return try context.fetch(descriptor).first
    }

    func save(_ page: PageEntity) async throws {
        insertIfNeeded(page, into: context)
        try coordinator.save()
    }

    func saveAll(_ pages: [PageEntity]) async throws {
        for page in pages {
            insertIfNeeded(page, into: context)
        }
        try coordinator.save()
    }

    func delete(_ page: PageEntity) async throws {
        removeDownloadedFile(at: page.localPath)
        context.delete(page)
        try coordinator.save()
    }

    func deleteAll(for chapterId: String) async throws {
        let pages = try await fetchByChapterId(chapterId)
        for page in pages {
            removeDownloadedFile(at: page.localPath)
            context.delete(page)
        }
        try coordinator.save()
    }

    func replaceAll(for chapterId: String, with pages: [PageEntity]) async throws {
        try coordinator.beginTransaction()
        do {
            let existing = try await fetchByChapterId(chapterId)
            for page in existing {
                removeDownloadedFile(at: page.localPath)
                context.delete(page)
            }
            for page in pages {
                insertIfNeeded(page, into: context)
            }
            try coordinator.commitTransaction()
        } catch {
            coordinator.rollbackTransaction()
            throw error
        }
    }

    func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws {
        guard let page = try await fetchById(pageId) else { return }
        if !isDownloaded {
            removeDownloadedFile(at: page.localPath)
        }
        page.isDownloaded = isDownloaded
        page.downloadedAt = isDownloaded ? Date() : nil
        page.localPath = isDownloaded ? localPath : nil
        try coordinator.save()
    }
}

@MainActor
final class SwiftDataReadingProgressRepository: ReadingProgressRepository {
    private let coordinator: PersistenceCoordinator

    private var context: ModelContext { coordinator.context }

    init(coordinator: PersistenceCoordinator) {
        self.coordinator = coordinator
    }

    func fetchByMangaId(_ mangaId: String) async throws -> [ReadingProgressEntity] {
        let descriptor = FetchDescriptor<ReadingProgressEntity>(
            predicate: #Predicate { $0.manga?.id == mangaId },
            sortBy: [SortDescriptor(\.readAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchByMangaIdAndChapterId(_ mangaId: String, chapterId: String) async throws -> [ReadingProgressEntity] {
        let descriptor = FetchDescriptor<ReadingProgressEntity>(
            predicate: #Predicate { $0.manga?.id == mangaId && $0.chapter?.id == chapterId },
            sortBy: [SortDescriptor(\.readAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchLatest(for mangaId: String) async throws -> ReadingProgressEntity? {
        var descriptor = FetchDescriptor<ReadingProgressEntity>(
            predicate: #Predicate { $0.manga?.id == mangaId },
            sortBy: [SortDescriptor(\.readAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func save(_ progress: ReadingProgressEntity) async throws {
        insertIfNeeded(progress, into: context)
        try coordinator.save()
    }

    func delete(_ progress: ReadingProgressEntity) async throws {
        context.delete(progress)
        try coordinator.save()
    }

    func deleteAll(for mangaId: String) async throws {
        let all = try await fetchByMangaId(mangaId)
        for progress in all {
            context.delete(progress)
        }
        try coordinator.save()
    }
}

@MainActor
final class SwiftDataBookmarkRepository: BookmarkRepository {
    private let coordinator: PersistenceCoordinator

    private var context: ModelContext { coordinator.context }

    init(coordinator: PersistenceCoordinator) {
        self.coordinator = coordinator
    }

    func fetchByMangaId(_ mangaId: String) async throws -> [BookmarkEntity] {
        let descriptor = FetchDescriptor<BookmarkEntity>(
            predicate: #Predicate { $0.manga?.id == mangaId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchByChapterId(_ chapterId: String) async throws -> [BookmarkEntity] {
        let descriptor = FetchDescriptor<BookmarkEntity>(
            predicate: #Predicate { $0.chapter?.id == chapterId },
            sortBy: [SortDescriptor(\.pageIndex, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchById(_ id: String) async throws -> BookmarkEntity? {
        let descriptor = FetchDescriptor<BookmarkEntity>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func save(_ bookmark: BookmarkEntity) async throws {
        insertIfNeeded(bookmark, into: context)
        try coordinator.save()
    }

    func delete(_ bookmark: BookmarkEntity) async throws {
        context.delete(bookmark)
        try coordinator.save()
    }

    func deleteAll(for mangaId: String) async throws {
        let bookmarks = try await fetchByMangaId(mangaId)
        for bookmark in bookmarks {
            context.delete(bookmark)
        }
        try coordinator.save()
    }
}

// MARK: - Site Profile Repository Implementation

@MainActor
final class SwiftDataSiteProfileRepository: SiteProfileRepository {
    private let coordinator: PersistenceCoordinator

    private var context: ModelContext { coordinator.context }

    init(coordinator: PersistenceCoordinator) {
        self.coordinator = coordinator
    }

    func fetchAll() async throws -> [SiteProfile] {
        let descriptor = FetchDescriptor<SiteProfileEntity>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try context.fetch(descriptor).map(\.profile)
    }

    func fetch(id: String) async throws -> SiteProfile? {
        try entity(id: id)?.profile
    }

    func fetchByBaseURL(_ baseURL: String) async throws -> SiteProfile? {
        let descriptor = FetchDescriptor<SiteProfileEntity>(
            predicate: #Predicate { $0.baseURL == baseURL }
        )
        return try context.fetch(descriptor).first?.profile
    }

    func save(_ profile: SiteProfile) async throws {
        if let existing = try entity(id: profile.id) {
            existing.apply(profile)
        } else {
            context.insert(SiteProfileEntity(profile: profile))
        }
        try coordinator.save()
    }

    func delete(_ profile: SiteProfile) async throws {
        guard let existing = try entity(id: profile.id) else {
            throw SiteProfileError.notFound(profile.id)
        }
        context.delete(existing)
        try coordinator.save()
    }

    private func entity(id: String) throws -> SiteProfileEntity? {
        let descriptor = FetchDescriptor<SiteProfileEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }
}
