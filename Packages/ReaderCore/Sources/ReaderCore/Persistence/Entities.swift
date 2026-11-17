// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

// MARK: - Manga Entity (SwiftData Model)

@Model
public final class MangaEntity {
    @Attribute(.unique) public var id: String
    public var title: String
    public var coverURL: String?
    public var altTitles: [String]
    public var authors: [String]
    public var artists: [String]
    public var synopsis: String?
    public var tags: [String]
    public var genres: [String]
    public var status: MangaStatus
    public var contentRating: ContentRating
    /// Whether chapters are image pages or prose.
    public var kind: ContentKind = ContentKind.comic
    public var lastReadAt: Date?
    public var lastReadChapterId: String?
    public var lastReadPageIndex: Int?
    /// Newest chapter the user had seen when they last opened the series.
    ///
    /// Chapters added after this point are "new": they drive the badge in the
    /// library without relying on push notifications.
    public var lastSeenChapterId: String?
    public var readingProgress: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var isFavorite: Bool

    // Source attribution.
    //
    // The link to a site profile is the value of `siteProfileID`, not a
    // SwiftData relationship: profiles are value types and the same store is
    // shared with adapters that only understand identifiers. Deleting a
    // profile therefore purges its library content explicitly in
    // `SitesViewModel.deleteProfile` (see DOM-04), which also removes the
    // media files that SwiftData could not cascade.
    public var siteProfileID: String?
    public var siteName: String?
    public var siteURL: String?
    public var siteLogoURL: String?
    public var siteCredits: String?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \ChapterEntity.manga) public var chapters: [ChapterEntity] = []
    @Relationship(deleteRule: .cascade, inverse: \BookmarkEntity.manga) public var bookmarks: [BookmarkEntity] = []
    @Relationship(deleteRule: .cascade, inverse: \ReadingProgressEntity.manga) public var readingProgressEntries:
        [ReadingProgressEntity] = []

    public init(
        id: String,
        title: String,
        coverURL: String? = nil,
        altTitles: [String] = [],
        authors: [String] = [],
        artists: [String] = [],
        synopsis: String? = nil,
        tags: [String] = [],
        genres: [String] = [],
        status: MangaStatus = .unknown,
        contentRating: ContentRating = .unknown,
        kind: ContentKind = .comic,
        isFavorite: Bool = false,
        siteProfileID: String? = nil,
        siteName: String? = nil,
        siteURL: String? = nil,
        siteLogoURL: String? = nil,
        siteCredits: String? = nil
    ) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.altTitles = altTitles
        self.authors = authors
        self.artists = artists
        self.synopsis = synopsis
        self.tags = tags
        self.genres = genres
        self.status = status
        self.contentRating = contentRating
        self.kind = kind
        self.lastReadAt = nil
        self.lastReadChapterId = nil
        self.lastReadPageIndex = nil
        self.lastSeenChapterId = nil
        self.readingProgress = 0.0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isFavorite = isFavorite
        self.siteProfileID = siteProfileID
        self.siteName = siteName
        self.siteURL = siteURL
        self.siteLogoURL = siteLogoURL
        self.siteCredits = siteCredits
    }

    /// Source attribution derived from the stored site fields.
    public var attribution: Attribution? {
        guard let siteName, let siteURL else { return nil }
        return Attribution(siteName: siteName, siteURL: siteURL, logoURL: siteLogoURL, credits: siteCredits)
    }

    /// Builds the stable identifier for a manga that belongs to a site profile.
    ///
    /// Adapter keys are only unique inside a single adapter, so the persisted
    /// identifier must include the site profile to avoid collisions.
    public static func makeID(siteProfileID: String, key: String) -> String {
        "\(siteProfileID)::\(key)"
    }

    /// Returns the adapter key, removing the site-profile prefix when present.
    ///
    /// Adapters only understand their own keys, while the persisted identifier
    /// may be scoped with `makeID(siteProfileID:key:)`.
    public var adapterKey: String {
        guard let siteProfileID else { return id }
        let prefix = "\(siteProfileID)::"
        guard id.hasPrefix(prefix) else { return id }
        return String(id.dropFirst(prefix.count))
    }

    /// Chapters in reading order.
    ///
    /// Numeric order first; chapters without a number go last. The identifier
    /// breaks ties so the order is stable across fetches.
    public var chaptersInReadingOrder: [ChapterEntity] {
        chapters.sorted { lhs, rhs in
            let left = lhs.number ?? .greatestFiniteMagnitude
            let right = rhs.number ?? .greatestFiniteMagnitude
            if left != right {
                return left < right
            }
            return lhs.id < rhs.id
        }
    }

    public func updateLastRead(chapterId: String, pageIndex: Int, totalPages: Int) {
        updateReadingPosition(chapterId: chapterId, pageIndex: pageIndex, totalPages: totalPages)
    }

    /// Chapters the site added after the user last looked at the list.
    ///
    /// Reading order is numeric, so new chapters land after the newest one
    /// the user saw. A marker that no longer exists (the chapter was removed
    /// upstream) reports zero instead of guessing.
    public var newChapterCount: Int {
        let ordered = chaptersInReadingOrder
        guard let lastSeenChapterId,
            let index = ordered.firstIndex(where: { $0.id == lastSeenChapterId })
        else { return 0 }
        return max(0, ordered.count - index - 1)
    }

    /// Marks every chapter currently known as seen.
    public func markChaptersSeen() {
        guard let newest = chaptersInReadingOrder.last else { return }
        lastSeenChapterId = newest.id
    }

    /// Updates the exact reading position.
    ///
    /// `pageIndex` is zero-based. The stored `readingProgress` is series-level:
    /// completed chapters count as whole units and the current chapter adds
    /// its own fraction. Reading the final page of the final chapter reaches
    /// `1.0`, while opening a chapter starts at that chapter's position in the
    /// series instead of showing the chapter as a fraction of the whole series.
    public func updateReadingPosition(chapterId: String, pageIndex: Int, totalPages: Int) {
        self.lastReadPageIndex = pageIndex

        let chapterFraction: Double
        if totalPages > 0 {
            chapterFraction = Double(min(pageIndex + 1, totalPages)) / Double(totalPages)
        } else {
            chapterFraction = 0
        }
        updateReadingPosition(chapterId: chapterId, chapterFraction: chapterFraction)
    }

    /// Updates the position from a chapter fraction.
    ///
    /// Text chapters have no pages to index, so their reader reports how much
    /// of the body was read instead. The series-level progress stays
    /// chapter-based: completed chapters count as whole units and the current
    /// one adds its own fraction.
    public func updateReadingPosition(chapterId: String, chapterFraction: Double) {
        self.lastReadAt = Date()
        self.lastReadChapterId = chapterId

        let fraction = min(max(chapterFraction, 0), 1)
        let ordered = chaptersInReadingOrder
        if !ordered.isEmpty,
            let index = ordered.firstIndex(where: { $0.id == chapterId })
        {
            self.readingProgress = (Double(index) + fraction) / Double(ordered.count)
        } else {
            self.readingProgress = fraction
        }
        self.updatedAt = Date()
    }
}

// MARK: - Chapter Entity

@Model
public final class ChapterEntity {
    @Attribute(.unique) public var id: String

    /// Original adapter key, without the site-profile prefix.
    ///
    /// Persisted separately so adapters can receive their own key even though
    /// the identifier is scoped to the site profile.
    public var sourceKey: String?
    public var title: String?
    public var number: Double?
    public var volume: Double?
    public var language: String?
    public var publishedAt: Date?
    public var group: String?
    public var pageCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) public var manga: MangaEntity?
    @Relationship(deleteRule: .cascade, inverse: \PageEntity.chapter) public var pages: [PageEntity] = []
    @Relationship(deleteRule: .nullify, inverse: \ReadingProgressEntity.chapter) public var readingProgressEntries:
        [ReadingProgressEntity] = []
    @Relationship(deleteRule: .nullify, inverse: \BookmarkEntity.chapter) public var bookmarks: [BookmarkEntity] = []
    /// Text of a prose chapter, fetched on demand.
    @Relationship(deleteRule: .cascade, inverse: \ChapterContentEntity.chapter) public var content:
        ChapterContentEntity?

    public init(
        id: String,
        sourceKey: String? = nil,
        title: String? = nil,
        number: Double? = nil,
        volume: Double? = nil,
        language: String? = nil,
        publishedAt: Date? = nil,
        group: String? = nil,
        pageCount: Int = 0
    ) {
        self.id = id
        self.sourceKey = sourceKey
        self.title = title
        self.number = number
        self.volume = volume
        self.language = language
        self.publishedAt = publishedAt
        self.group = group
        self.pageCount = pageCount
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Latest recorded reading fraction for this chapter, from 0 to 1.
    public var recordedProgress: Double {
        readingProgressEntries.max(by: { $0.readAt < $1.readAt })?.progress ?? 0
    }

    /// Whether the last page of the chapter has been reached.
    ///
    /// The comparison tolerates the rounding of `progress`, which is stored as
    /// `(pageIndex + 1) / totalPages`.
    public var isRead: Bool {
        recordedProgress >= 1.0 - 0.0001
    }

    /// Returns the adapter key, removing the site-profile prefix when present.
    ///
    /// Adapters only understand their own keys, while the persisted identifier
    /// is scoped with `<siteProfileID>::<chapterKey>` to avoid collisions.
    public var adapterKey: String {
        if let sourceKey {
            return sourceKey
        }
        guard let mangaProfileID = manga?.siteProfileID else { return id }
        let prefix = "\(mangaProfileID)::"
        guard id.hasPrefix(prefix) else { return id }
        return String(id.dropFirst(prefix.count))
    }
}

// MARK: - Page Entity

@Model
public final class PageEntity {
    @Attribute(.unique) public var id: String
    public var index: Int
    public var imageURL: String
    public var headers: [String: String]?
    public var width: Int?
    public var height: Int?
    public var createdAt: Date
    public var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) public var chapter: ChapterEntity?

    public init(
        id: String = UUID().uuidString,
        index: Int,
        imageURL: String,
        headers: [String: String]? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.index = index
        self.imageURL = imageURL
        self.headers = headers
        self.width = width
        self.height = height
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Reading Progress Entity

@Model
public final class ReadingProgressEntity {
    @Attribute(.unique) public var id: String
    public var pageIndex: Int
    public var totalPages: Int
    /// How far the reader scrolled into `pageIndex`, from 0 to 1.
    ///
    /// Pages do not share a ratio: for a long image the page index alone
    /// restores the top of the strip, losing the reader's place.
    public var pageOffsetFraction: Double = 0
    /// Character offset for prose chapters, where there are no pages.
    public var textOffset: Int?
    public var progress: Double  // 0.0 to 1.0
    public var readAt: Date
    public var updatedAt: Date
    public var timeSpent: TimeInterval  // seconds spent reading this session

    // Relationships
    @Relationship(deleteRule: .nullify) public var manga: MangaEntity?
    @Relationship(deleteRule: .nullify) public var chapter: ChapterEntity?

    public init(
        id: String = UUID().uuidString,
        pageIndex: Int,
        totalPages: Int,
        manga: MangaEntity,
        chapter: ChapterEntity? = nil,
        pageOffsetFraction: Double = 0,
        textOffset: Int? = nil,
        timeSpent: TimeInterval = 0
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.totalPages = totalPages
        self.pageOffsetFraction = min(max(pageOffsetFraction, 0), 1)
        self.textOffset = textOffset
        self.progress = totalPages > 0 ? Double(min(pageIndex + 1, totalPages)) / Double(totalPages) : 0.0
        self.readAt = Date()
        self.updatedAt = Date()
        self.timeSpent = timeSpent
        self.manga = manga
        self.chapter = chapter
    }

    public var progressPercentage: Int {
        Int(progress * 100)
    }
}

// MARK: - Bookmark Entity

@Model
public final class BookmarkEntity {
    @Attribute(.unique) public var id: String
    public var note: String?
    public var pageIndex: Int
    /// Character offset for prose chapters, where there are no pages.
    public var textOffset: Int?
    public var createdAt: Date
    public var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) public var manga: MangaEntity?
    @Relationship(deleteRule: .nullify) public var chapter: ChapterEntity?

    public init(
        id: String = UUID().uuidString,
        note: String? = nil,
        pageIndex: Int,
        manga: MangaEntity,
        chapter: ChapterEntity? = nil,
        textOffset: Int? = nil
    ) {
        self.id = id
        self.note = note
        self.pageIndex = pageIndex
        self.textOffset = textOffset
        self.createdAt = Date()
        self.updatedAt = Date()
        self.manga = manga
        self.chapter = chapter
    }
}

// MARK: - Display Helpers

extension MangaStatus {
    public var displayName: String {
        switch self {
        case .ongoing: return "Ongoing"
        case .completed: return "Completed"
        case .hiatus: return "On Hiatus"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }
}

extension ContentRating {
    public var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .suggestive: return "Suggestive"
        case .mature: return "Mature"
        case .unknown: return "Unknown"
        }
    }
}

extension MangaEntity {
    public var displayTitle: String { title }

    public var authorsDisplay: String { authors.joined(separator: ", ") }

    public var artistsDisplay: String { artists.joined(separator: ", ") }

    public var tagsDisplay: String { tags.joined(separator: ", ") }

    public var latestChapter: ChapterEntity? {
        chapters.max { lhs, rhs in
            (lhs.number ?? -Double.infinity) < (rhs.number ?? -Double.infinity)
        }
    }
}

// MARK: - Chapter Content Entity

/// Text of a prose chapter, fetched on demand.
///
/// Prose has no pages: the adapter returns the chapter body as HTML and the
/// reader renders it. The body is cached so reopening a chapter does not hit
/// the site again, but it is not sync data: it can always be fetched again.
/// File formats (EPUB, PDF) are out of scope.
@Model
public final class ChapterContentEntity {
    @Attribute(.unique) public var id: String
    /// Chapter body as returned by the adapter, before rendering.
    public var body: String
    /// Serialized `TextFormat` raw value.
    public var formatRaw: String
    public var wordCount: Int
    /// Length of `body` in characters, used for the chapter percentage.
    public var characterCount: Int
    public var fetchedAt: Date
    public var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) public var chapter: ChapterEntity?

    public init(
        id: String = UUID().uuidString,
        body: String,
        format: TextFormat = .html,
        wordCount: Int = 0,
        chapter: ChapterEntity? = nil
    ) {
        self.id = id
        self.body = body
        self.formatRaw = format.rawValue
        self.wordCount = wordCount
        self.characterCount = body.count
        self.fetchedAt = Date()
        self.updatedAt = Date()
        self.chapter = chapter
    }

    public var format: TextFormat {
        get { TextFormat(rawValue: formatRaw) ?? .html }
        set { formatRaw = newValue.rawValue }
    }

    /// How much of the body has been read for a character offset.
    ///
    /// This is the chapter percentage for prose: pages are a rendering
    /// artifact, characters are not. An empty body reports zero.
    public func fraction(forOffset offset: Int) -> Double {
        guard characterCount > 0 else { return 0 }
        return min(max(Double(offset) / Double(characterCount), 0), 1)
    }
}

// MARK: - Sync Tombstone Entity

/// Record of a deletion, kept so a sync can propagate it.
///
/// Without tombstones, a series removed on one device would be re-created by
/// the next merge from a device that still has it. Only user-visible records
/// get tombstones: pages and cached chapter text are derived data.
@Model
public final class SyncTombstoneEntity {
    @Attribute(.unique) public var id: String
    /// Serialized `SyncRecordKind` raw value.
    public var recordKindRaw: String
    public var recordID: String
    public var deletedAt: Date

    public init(kind: SyncRecordKind, recordID: String, deletedAt: Date = Date()) {
        self.id = Self.makeID(kind: kind, recordID: recordID)
        self.recordKindRaw = kind.rawValue
        self.recordID = recordID
        self.deletedAt = deletedAt
    }

    public var recordKind: SyncRecordKind? {
        SyncRecordKind(rawValue: recordKindRaw)
    }

    public static func makeID(kind: SyncRecordKind, recordID: String) -> String {
        "\(kind.rawValue):\(recordID)"
    }
}
