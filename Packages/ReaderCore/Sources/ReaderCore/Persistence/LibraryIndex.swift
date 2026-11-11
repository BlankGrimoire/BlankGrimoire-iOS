// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

/// Immutable snapshot of a library row.
///
/// The library grid needs to filter and sort the whole collection, but it does
/// not need the SwiftData model objects. Reading the snapshot on a background
/// `ModelActor` keeps a large library from blocking the main actor (REP-01).
public struct LibraryEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let coverURL: String?
    public let authors: [String]
    public let tags: [String]
    public let status: MangaStatus
    public let isFavorite: Bool
    public let readingProgress: Double
    public let lastReadAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
    public let siteName: String?

    public init(entity: MangaEntity) {
        self.id = entity.id
        self.title = entity.title
        self.coverURL = entity.coverURL
        self.authors = entity.authors
        self.tags = entity.tags
        self.status = entity.status
        self.isFavorite = entity.isFavorite
        self.readingProgress = entity.readingProgress
        self.lastReadAt = entity.lastReadAt
        self.createdAt = entity.createdAt
        self.updatedAt = entity.updatedAt
        self.siteName = entity.siteName
    }

    /// Returns a copy with a new favorite state, used for optimistic updates.
    public func withFavorite(_ isFavorite: Bool) -> LibraryEntry {
        LibraryEntry(
            id: id,
            title: title,
            coverURL: coverURL,
            authors: authors,
            tags: tags,
            status: status,
            isFavorite: isFavorite,
            readingProgress: readingProgress,
            lastReadAt: lastReadAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            siteName: siteName
        )
    }

    private init(
        id: String,
        title: String,
        coverURL: String?,
        authors: [String],
        tags: [String],
        status: MangaStatus,
        isFavorite: Bool,
        readingProgress: Double,
        lastReadAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        siteName: String?
    ) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.authors = authors
        self.tags = tags
        self.status = status
        self.isFavorite = isFavorite
        self.readingProgress = readingProgress
        self.lastReadAt = lastReadAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.siteName = siteName
    }
}

/// Reads the library snapshot off the main actor.
@ModelActor
public actor LibraryIndexReader {
    public func entries() throws -> [LibraryEntry] {
        let descriptor = FetchDescriptor<MangaEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(LibraryEntry.init)
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<MangaEntity>())
    }
}
