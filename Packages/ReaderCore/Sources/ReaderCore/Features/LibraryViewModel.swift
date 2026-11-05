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
    public var manga: [MangaEntity] = []
    public var searchText: String = ""
    public var sortOption: LibrarySortOption = .recentlyRead
    public var filterOption: LibraryFilterOption = .all
    public var isLoading: Bool = false
    public var lastError: Error?

    private let mangaRepository: any MangaRepository

    public init(mangaRepository: any MangaRepository) {
        self.mangaRepository = mangaRepository
    }

    /// Filtered and sorted manga list
    public var filteredManga: [MangaEntity] {
        var result = manga

        if !searchText.isEmpty {
            result = result.filter { manga in
                manga.title.localizedCaseInsensitiveContains(searchText)
                    || manga.authors.contains { $0.localizedCaseInsensitiveContains(searchText) }
                    || manga.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
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

        switch sortOption {
        case .recentlyRead:
            result.sort { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .titleDescending:
            result.sort { $0.title.localizedCompare($1.title) == .orderedDescending }
        case .recentlyAdded:
            result.sort { $0.createdAt > $1.createdAt }
        case .progress:
            result.sort { $0.readingProgress > $1.readingProgress }
        }

        return result
    }

    /// Load manga from repository
    public func loadManga() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            manga = try await mangaRepository.fetchAll()
        } catch {
            lastError = error
        }
    }

    /// Toggle favorite status
    public func toggleFavorite(_ manga: MangaEntity) async {
        let previousValue = manga.isFavorite
        manga.isFavorite.toggle()

        do {
            try await mangaRepository.save(manga)
        } catch {
            manga.isFavorite = previousValue
            lastError = error
        }
    }

    /// Delete manga
    public func deleteManga(_ manga: MangaEntity) async {
        do {
            try await mangaRepository.delete(manga)
            await loadManga()
        } catch {
            lastError = error
        }
    }
}
