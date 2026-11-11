// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

// MARK: - Persistence Errors

/// Errors raised by the persistence coordinator.
public enum PersistenceError: Error, LocalizedError, Sendable {
    case transactionAlreadyInProgress
    case nestedTransaction
    case recordNotFound(entity: String, id: String)
    case invalidLocalPath(String)

    public var errorDescription: String? {
        switch self {
        case .transactionAlreadyInProgress:
            return "A persistence transaction is already in progress"
        case .nestedTransaction:
            return "Nested persistence transactions are not supported"
        case .recordNotFound(let entity, let id):
            return "No \(entity) found for id \(id)"
        case .invalidLocalPath(let path):
            return "Refusing to use a file outside the app container: \(path)"
        }
    }
}

// MARK: - Persistence Coordinator

/// Owns the SwiftData context and coordinates saves inside transactions.
@MainActor
final class PersistenceCoordinator {
    let context: ModelContext
    /// The container backing ``context``.
    ///
    /// Background readers (for example `LibraryIndexReader`) create their own
    /// `ModelContext` from it instead of touching the main-actor context.
    let container: ModelContainer

    private var isInTransaction = false

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    /// Saves immediately unless a transaction is in progress. Transactions
    /// persist once at commit time so they can still be rolled back.
    func save() throws {
        guard !isInTransaction else { return }
        try context.save()
    }

    /// Starts a transaction. Nested transactions are rejected instead of being
    /// flattened by a counter, so a failure always rolls back the whole unit.
    func beginTransaction() throws {
        guard !isInTransaction else {
            throw PersistenceError.transactionAlreadyInProgress
        }
        isInTransaction = true
    }

    func commitTransaction() throws {
        guard isInTransaction else { return }
        isInTransaction = false
        try context.save()
    }

    func rollbackTransaction() {
        isInTransaction = false
        context.rollback()
    }

    /// Rolls back pending changes only when no transaction owns the context.
    func rollbackOutsideTransaction() throws {
        guard !isInTransaction else {
            throw PersistenceError.transactionAlreadyInProgress
        }
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
    public let siteProfiles: SiteProfileRepository

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
        self.siteProfiles = SwiftDataSiteProfileRepository(coordinator: coordinator)
    }

    public func saveContext() async throws {
        try coordinator.save()
    }

    public func rollback() async throws {
        try coordinator.rollbackOutsideTransaction()
    }

    public func performInTransaction<T>(_ operation: () async throws -> T) async throws -> T {
        try coordinator.beginTransaction()
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
            let container = try BlankGrimoireSchema.makeContainer(
                isStoredInMemoryOnly: true,
                name: "Test"
            )
            return try SwiftDataPersistenceManager(container: container)
        }
    }
#endif
