// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

/// Records that take part in sync.
///
/// Pages and cached chapter text are deliberately absent: they are derived
/// from the site and can be fetched again on any device.
public enum SyncRecordKind: String, Codable, Sendable, CaseIterable {
    case manga
    case chapter
    case readingProgress
    case bookmark
    case siteProfile
    case trustedRepository
    case installedAdapter
}

/// Writes tombstones for deleted records.
///
/// A sync merges records; without a tombstone, a record deleted on one device
/// would come back from another one that still had it. Recording is
/// idempotent: deleting the same record twice keeps a single tombstone.
@MainActor
enum SyncTombstoneRecorder {
    static func record(
        _ kind: SyncRecordKind,
        ids: [String],
        in context: ModelContext,
        at date: Date = Date()
    ) throws {
        guard !ids.isEmpty else { return }

        let tombstoneIDs = ids.map { SyncTombstoneEntity.makeID(kind: kind, recordID: $0) }
        let descriptor = FetchDescriptor<SyncTombstoneEntity>(
            predicate: #Predicate { tombstoneIDs.contains($0.id) }
        )
        var existing = Dictionary(
            try context.fetch(descriptor).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (id, tombstoneID) in zip(ids, tombstoneIDs) {
            if let tombstone = existing[tombstoneID] {
                tombstone.deletedAt = date
            } else {
                let tombstone = SyncTombstoneEntity(kind: kind, recordID: id, deletedAt: date)
                context.insert(tombstone)
                existing[tombstoneID] = tombstone
            }
        }
    }

    /// Records a series and everything that hangs off it.
    ///
    /// Deleting a series cascades in the store, so the sync needs a tombstone
    /// per child record as well.
    static func recordMangaDeletion(_ manga: MangaEntity, in context: ModelContext) throws {
        try record(.chapter, ids: manga.chapters.map(\.id), in: context)
        try record(.readingProgress, ids: manga.readingProgressEntries.map(\.id), in: context)
        try record(.bookmark, ids: manga.bookmarks.map(\.id), in: context)
        try record(.manga, ids: [manga.id], in: context)

        for chapter in manga.chapters {
            try record(
                .readingProgress,
                ids: chapter.readingProgressEntries.map(\.id),
                in: context
            )
            try record(.bookmark, ids: chapter.bookmarks.map(\.id), in: context)
        }
    }
}
