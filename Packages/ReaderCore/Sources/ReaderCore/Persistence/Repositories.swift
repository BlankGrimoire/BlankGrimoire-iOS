// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

// The SwiftData models live in Domain/Entities.swift. The contract DTOs with
// the same concepts live in Models.swift; persistence works with the entity
// types so that adapter payloads never leak into the local store.

// MARK: - Repository Protocols

/// Protocol for manga persistence operations
@MainActor
public protocol MangaRepository {
    func fetchAll() async throws -> [MangaEntity]
    func fetchById(_ id: String) async throws -> MangaEntity?
    func fetchByIds(_ ids: [String]) async throws -> [MangaEntity]
    func fetchFavorites() async throws -> [MangaEntity]
    func fetchRecent(limit: Int) async throws -> [MangaEntity]
    func fetchByStatus(_ status: MangaStatus) async throws -> [MangaEntity]
    func fetchByTag(_ tag: String) async throws -> [MangaEntity]
    func search(query: String) async throws -> [MangaEntity]
    func save(_ manga: MangaEntity) async throws
    func delete(_ manga: MangaEntity) async throws
    func deleteAll() async throws
    func count() async throws -> Int
}

/// Protocol for chapter persistence operations
@MainActor
public protocol ChapterRepository {
    func fetchByMangaId(_ mangaId: String) async throws -> [ChapterEntity]
    func fetchById(_ id: String) async throws -> ChapterEntity?
    func fetchByMangaIdAndNumber(_ mangaId: String, number: Double) async throws -> ChapterEntity?
    func fetchByIds(_ ids: [String]) async throws -> [ChapterEntity]
    func fetchDownloadedChapters(for mangaId: String) async throws -> [ChapterEntity]
    func save(_ chapter: ChapterEntity) async throws
    func saveAll(_ chapters: [ChapterEntity]) async throws
    func delete(_ chapter: ChapterEntity) async throws
    func deleteAll(for mangaId: String) async throws
    func updateDownloadStatus(_ chapterId: String, isDownloaded: Bool, downloadedPagesCount: Int) async throws
}

/// Protocol for page persistence operations
@MainActor
public protocol PageRepository {
    func fetchByChapterId(_ chapterId: String) async throws -> [PageEntity]
    func fetchById(_ id: String) async throws -> PageEntity?
    func fetchByChapterIdAndIndex(_ chapterId: String, index: Int) async throws -> PageEntity?
    func save(_ page: PageEntity) async throws
    func saveAll(_ pages: [PageEntity]) async throws
    func delete(_ page: PageEntity) async throws
    func deleteAll(for chapterId: String) async throws
    func updateDownloadStatus(_ pageId: String, isDownloaded: Bool, localPath: String?) async throws
}

/// Protocol for reading progress persistence
@MainActor
public protocol ReadingProgressRepository {
    func fetchByMangaId(_ mangaId: String) async throws -> [ReadingProgressEntity]
    func fetchByMangaIdAndChapterId(_ mangaId: String, chapterId: String) async throws -> [ReadingProgressEntity]
    func fetchLatest(for mangaId: String) async throws -> ReadingProgressEntity?
    func save(_ progress: ReadingProgressEntity) async throws
    func delete(_ progress: ReadingProgressEntity) async throws
    func deleteAll(for mangaId: String) async throws
}

/// Protocol for bookmark persistence
@MainActor
public protocol BookmarkRepository {
    func fetchByMangaId(_ mangaId: String) async throws -> [BookmarkEntity]
    func fetchByChapterId(_ chapterId: String) async throws -> [BookmarkEntity]
    func fetchById(_ id: String) async throws -> BookmarkEntity?
    func save(_ bookmark: BookmarkEntity) async throws
    func delete(_ bookmark: BookmarkEntity) async throws
    func deleteAll(for mangaId: String) async throws
}

// MARK: - Composite Repository Protocol

/// Main repository aggregator for all persistence operations
@MainActor
public protocol PersistenceManager {
    var mangas: MangaRepository { get }
    var chapters: ChapterRepository { get }
    var pages: PageRepository { get }
    var readingProgress: ReadingProgressRepository { get }
    var bookmarks: BookmarkRepository { get }

    func saveContext() async throws
    func rollback() async throws
    func performInTransaction<T>(_ operation: () async throws -> T) async throws -> T
}
