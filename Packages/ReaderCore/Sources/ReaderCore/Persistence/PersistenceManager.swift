// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

// MARK: - Persistence Coordinator

/// Owns the SwiftData context and coordinates saves inside transactions.
@MainActor
final class PersistenceCoordinator {
    let context: ModelContext

    private var transactionDepth = 0

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    /// Saves immediately unless a transaction is in progress. Transactions
    /// persist once at commit time so they can still be rolled back.
    func save() throws {
        guard transactionDepth == 0 else { return }
        try context.save()
    }

    func beginTransaction() {
        transactionDepth += 1
    }

    func commitTransaction() throws {
        transactionDepth = max(0, transactionDepth - 1)
        guard transactionDepth == 0 else { return }
        try context.save()
    }

    func rollbackTransaction() {
        transactionDepth = 0
        context.rollback()
    }
}

// MARK: - Persistence Manager Implementation

@MainActor
public final class SwiftDataPersistenceManager: PersistenceManager {
    public let mangas: MangaRepository
    public let chapters: ChapterRepository
    public let pages: PageRepository
    public let readingProgress: ReadingProgressRepository
    public let bookmarks: BookmarkRepository

    private let coordinator: PersistenceCoordinator

    public init(container: ModelContainer) throws {
        let coordinator = PersistenceCoordinator(container: container)
        self.coordinator = coordinator

        // Initialize repositories with the shared context
        self.mangas = SwiftDataMangaRepository(coordinator: coordinator)
        self.chapters = SwiftDataChapterRepository(coordinator: coordinator)
        self.pages = SwiftDataPageRepository(coordinator: coordinator)
        self.readingProgress = SwiftDataReadingProgressRepository(coordinator: coordinator)
        self.bookmarks = SwiftDataBookmarkRepository(coordinator: coordinator)
    }

    public func saveContext() async throws {
        try coordinator.save()
    }

    public func rollback() async throws {
        coordinator.rollbackTransaction()
    }

    public func performInTransaction<T>(_ operation: () async throws -> T) async throws -> T {
        coordinator.beginTransaction()
        do {
            let result = try await operation()
            try coordinator.commitTransaction()
            return result
        } catch {
            coordinator.rollbackTransaction()
            throw error
        }
    }

    // MARK: - Schema Migration

    /// Performs lightweight migration if needed
    static func performMigrationIfNeeded() async throws {
        // SwiftData handles lightweight migrations automatically.
        // For heavy migrations we would implement a custom migration plan.
    }
}

// MARK: - Preview/Testing Support

#if DEBUG
    extension SwiftDataPersistenceManager {
        /// Creates an in-memory persistence manager for testing
        static func createInMemory() throws -> SwiftDataPersistenceManager {
            let schema = Schema([
                MangaEntity.self,
                ChapterEntity.self,
                PageEntity.self,
                ReadingProgressEntity.self,
                BookmarkEntity.self,
            ])

            let configuration = ModelConfiguration(
                "Test",
                isStoredInMemoryOnly: true
            )

            let container = try ModelContainer(for: schema, configurations: [configuration])
            return try SwiftDataPersistenceManager(container: container)
        }
    }
#endif
