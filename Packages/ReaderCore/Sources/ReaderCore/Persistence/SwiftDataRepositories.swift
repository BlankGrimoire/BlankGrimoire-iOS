// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

// MARK: - SwiftData Repository Implementation

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
        let descriptor = FetchDescriptor<MangaEntity>(
            predicate: #Predicate { $0.status == status },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
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
        context.insert(manga)
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
        context.insert(chapter)
        try coordinator.save()
    }

    func saveAll(_ chapters: [ChapterEntity]) async throws {
        for chapter in chapters {
            chapter.updatedAt = Date()
            context.insert(chapter)
        }
        try coordinator.save()
    }

    func delete(_ chapter: ChapterEntity) async throws {
        context.delete(chapter)
        try coordinator.save()
    }

    func deleteAll(for mangaId: String) async throws {
        let chapters = try await fetchByMangaId(mangaId)
        for chapter in chapters {
            context.delete(chapter)
        }
        try coordinator.save()
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
        context.insert(page)
        try coordinator.save()
    }

    func saveAll(_ pages: [PageEntity]) async throws {
        for page in pages {
            context.insert(page)
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

    func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws {
        guard let page = try await fetchById(pageId) else { return }
        page.isDownloaded = isDownloaded
        page.downloadedAt = isDownloaded ? Date() : nil
        page.localPath = localPath
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
        context.insert(progress)
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
        context.insert(bookmark)
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
