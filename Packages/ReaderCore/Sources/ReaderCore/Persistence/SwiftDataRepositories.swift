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

/// Returns whether a SwiftData failure is the older runtime's refusal to
/// translate captured enum constants in a predicate.
private func isUnsupportedPredicate(_ error: Error) -> Bool {
    let description = String(describing: error)
    return description.contains("unsupportedPredicate")
        || description.localizedCaseInsensitiveContains("Unsupported Predicate")
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

    /// Reads the library snapshot on a background model context.
    ///
    /// The main context stays free while a large store is mapped into value
    /// types; the UI only receives `LibraryEntry` values.
    func fetchLibraryIndex() async throws -> [LibraryEntry] {
        let reader = LibraryIndexReader(modelContainer: coordinator.container)
        return try await reader.entries()
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
        // Filter in the store: loading the whole library on the main actor
        // makes every filter change O(library size) in memory.
        let descriptor = FetchDescriptor<MangaEntity>(
            predicate: #Predicate { $0.status == status },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            // Older SwiftData runtimes reject captured enum constants in
            // predicates (`unsupportedPredicate`). Only that limitation falls
            // back to an in-memory filter; any other failure is a real error.
            guard isUnsupportedPredicate(error) else { throw error }
            let all = try await fetchAll()
            return all.filter { $0.status == status }
        }
    }

    func fetchByTag(_ tag: String) async throws -> [MangaEntity] {
        // `tags` is a transformable string array. SwiftData's predicate
        // compiler accepts `.contains` for it but the store traps at runtime,
        // so the filter stays in memory until tags get their own relation.
        let all = try await fetchAll()
        return all.filter { $0.tags.contains(tag) }
    }

    func search(query: String) async throws -> [MangaEntity] {
        // Same limitation as `fetchByTag`: authors and tags are transformable
        // arrays and cannot be queried safely from a predicate.
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
        try SyncTombstoneRecorder.recordMangaDeletion(manga, in: context)
        context.delete(manga)
        try coordinator.save()
    }

    func deleteAll() async throws {
        let all = try await fetchAll()
        for manga in all {
            try SyncTombstoneRecorder.recordMangaDeletion(manga, in: context)
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
        // Chapter numbers are fractional and stored as `Double`: equality would
        // miss values produced by different decimal paths (1.1 vs 1.1000001).
        let chapters = try await fetchByMangaId(mangaId)
        return chapters.first { chapter in
            guard let value = chapter.number else { return false }
            return abs(value - number) < 0.000_001
        }
    }

    func fetchByIds(_ ids: [String]) async throws -> [ChapterEntity] {
        let descriptor = FetchDescriptor<ChapterEntity>(predicate: #Predicate { ids.contains($0.id) })
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

    /// Deletes a chapter's pages.
    private func deletePages(for chapter: ChapterEntity) throws {
        let chapterID = chapter.id
        let descriptor = FetchDescriptor<PageEntity>(
            predicate: #Predicate { $0.chapter?.id == chapterID }
        )
        for page in try context.fetch(descriptor) {
            context.delete(page)
        }
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
        page.updatedAt = Date()
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
        context.delete(page)
        try coordinator.save()
    }

    func deleteAll(for chapterId: String) async throws {
        let pages = try await fetchByChapterId(chapterId)
        for page in pages {
            context.delete(page)
        }
        try coordinator.save()
    }

    func replaceAll(for chapterId: String, with pages: [PageEntity]) async throws {
        try coordinator.beginTransaction()
        do {
            let existing = try await fetchByChapterId(chapterId)
            for page in existing {
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
        progress.updatedAt = Date()
        // A series/chapter pair must have a single row: repeated saves with a
        // new identifier would otherwise grow the table without limit.
        if let mangaID = progress.manga?.id, let chapterID = progress.chapter?.id {
            let existing = try await fetchByMangaIdAndChapterId(mangaID, chapterId: chapterID)
            for row in existing where row.id != progress.id {
                context.delete(row)
            }
        }
        insertIfNeeded(progress, into: context)
        try coordinator.save()
    }

    func delete(_ progress: ReadingProgressEntity) async throws {
        try SyncTombstoneRecorder.record(.readingProgress, ids: [progress.id], in: context)
        context.delete(progress)
        try coordinator.save()
    }

    func deleteAll(for mangaId: String) async throws {
        let all = try await fetchByMangaId(mangaId)
        try SyncTombstoneRecorder.record(.readingProgress, ids: all.map(\.id), in: context)
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
        bookmark.updatedAt = Date()
        insertIfNeeded(bookmark, into: context)
        try coordinator.save()
    }

    func delete(_ bookmark: BookmarkEntity) async throws {
        try SyncTombstoneRecorder.record(.bookmark, ids: [bookmark.id], in: context)
        context.delete(bookmark)
        try coordinator.save()
    }

    func deleteAll(for mangaId: String) async throws {
        let bookmarks = try await fetchByMangaId(mangaId)
        try SyncTombstoneRecorder.record(.bookmark, ids: bookmarks.map(\.id), in: context)
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

    func saveIfAbsent(_ profile: SiteProfile) async throws {
        if try entity(id: profile.id) != nil {
            throw SiteProfileError.alreadyExists(profile.baseURL)
        }
        let descriptor = FetchDescriptor<SiteProfileEntity>(
            predicate: #Predicate { $0.baseURL == profile.baseURL }
        )
        if try !context.fetch(descriptor).isEmpty {
            throw SiteProfileError.alreadyExists(profile.baseURL)
        }
        context.insert(SiteProfileEntity(profile: profile))
        try coordinator.save()
    }

    func delete(_ profile: SiteProfile) async throws {
        guard let existing = try entity(id: profile.id) else {
            throw SiteProfileError.notFound(profile.id)
        }
        try SyncTombstoneRecorder.record(.siteProfile, ids: [profile.id], in: context)
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
