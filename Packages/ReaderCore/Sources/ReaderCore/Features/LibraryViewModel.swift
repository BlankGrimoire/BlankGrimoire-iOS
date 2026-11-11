// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// Sort options for the library
public enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recentlyRead = "Recently Read"
    case title = "Title (A-Z)"
    case titleDescending = "Title (Z-A)"
    case recentlyAdded = "Recently Added"
    case progress = "Reading Progress"

    public var id: String { rawValue }
}

/// Filter options for the library
public enum LibraryFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case favorites = "Favorites"
    case inProgress = "In Progress"
    case completed = "Completed"
    case unread = "Unread"

    public var id: String { rawValue }
}

/// View model for the library
@MainActor
@Observable
public final class LibraryViewModel {
    /// All series known to the library. Assigning a new list rebuilds the view.
    ///
    /// The library works on `LibraryEntry` snapshots rather than live SwiftData
    /// objects: filtering and sorting happen on the main actor, but the store
    /// is read in the background (REP-01).
    public var manga: [LibraryEntry] = [] {
        didSet { rebuildVisibleManga() }
    }

    public var searchText: String = "" {
        didSet { rebuildVisibleManga() }
    }

    public var sortOption: LibrarySortOption = .recentlyRead {
        didSet { rebuildVisibleManga() }
    }

    public var filterOption: LibraryFilterOption = .all {
        didSet { rebuildVisibleManga() }
    }

    public var isLoading: Bool = false
    public var lastError: Error?

    /// Filtered and sorted list, rebuilt only when an input changes.
    ///
    /// SwiftUI reads this property on every render; recomputing the whole
    /// library there made large libraries janky on the main actor.
    public private(set) var filteredManga: [LibraryEntry] = []

    private let mangaRepository: any MangaRepository

    public init(mangaRepository: any MangaRepository) {
        self.mangaRepository = mangaRepository
        rebuildVisibleManga()
    }

    private func rebuildVisibleManga() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = manga

        if !query.isEmpty {
            result = result.filter { manga in
                manga.title.localizedCaseInsensitiveContains(query)
                    || manga.authors.contains { $0.localizedCaseInsensitiveContains(query) }
                    || manga.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }

        switch filterOption {
        case .all:
            break
        case .favorites:
            result = result.filter(\.isFavorite)
        case .inProgress:
            result = result.filter { $0.readingProgress > 0 && $0.readingProgress < 1.0 }
        case .completed:
            result = result.filter { $0.readingProgress >= 1.0 }
        case .unread:
            result = result.filter { $0.readingProgress == 0 }
        }

        result.sort(by: sortComparator)

        // A stable secondary order keeps equal entries from jumping between
        // renders (for example series that were never read).
        filteredManga = result
    }

    private func sortComparator(_ lhs: LibraryEntry, _ rhs: LibraryEntry) -> Bool {
        let primary: ComparisonResult
        switch sortOption {
        case .recentlyRead:
            primary = compare(rhs.lastReadAt ?? .distantPast, lhs.lastReadAt ?? .distantPast)
        case .title:
            primary = lhs.title.localizedStandardCompare(rhs.title)
        case .titleDescending:
            primary = rhs.title.localizedStandardCompare(lhs.title)
        case .recentlyAdded:
            primary = compare(rhs.createdAt, lhs.createdAt)
        case .progress:
            primary = compare(rhs.readingProgress, lhs.readingProgress)
        }

        if primary != .orderedSame {
            return primary == .orderedAscending
        }
        if lhs.title.localizedStandardCompare(rhs.title) != .orderedSame {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    /// Load manga from repository
    public func loadManga() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            manga = try await mangaRepository.fetchLibraryIndex()
        } catch {
            lastError = error
        }
    }

    /// Toggle favorite status.
    ///
    /// The list holds snapshots, so the write goes through the persisted
    /// entity and the snapshot is updated in place on success.
    public func toggleFavorite(_ entry: LibraryEntry) async {
        do {
            guard let entity = try await mangaRepository.fetchById(entry.id) else {
                lastError = PersistenceError.recordNotFound(entity: "MangaEntity", id: entry.id)
                return
            }
            let previousValue = entity.isFavorite
            entity.isFavorite.toggle()

            do {
                try await mangaRepository.save(entity)
                replaceEntry(entry.withFavorite(entity.isFavorite))
            } catch {
                entity.isFavorite = previousValue
                throw error
            }
        } catch {
            lastError = error
        }
    }

    /// Delete manga and its downloaded content.
    public func deleteManga(_ entry: LibraryEntry) async {
        do {
            guard let entity = try await mangaRepository.fetchById(entry.id) else {
                // Already gone in the store: drop the stale row anyway.
                manga.removeAll { $0.id == entry.id }
                return
            }
            try await mangaRepository.delete(entity)
            manga.removeAll { $0.id == entry.id }
        } catch {
            lastError = error
        }
    }

    private func replaceEntry(_ entry: LibraryEntry) {
        guard let index = manga.firstIndex(where: { $0.id == entry.id }) else { return }
        manga[index] = entry
    }
}
