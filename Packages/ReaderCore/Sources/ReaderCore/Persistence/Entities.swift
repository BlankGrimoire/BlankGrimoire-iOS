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
    public var status: MangaStatus
    public var contentRating: ContentRating
    public var lastReadAt: Date?
    public var lastReadChapterId: String?
    public var lastReadPageIndex: Int?
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
        status: MangaStatus = .unknown,
        contentRating: ContentRating = .unknown,
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
        self.status = status
        self.contentRating = contentRating
        self.lastReadAt = nil
        self.lastReadChapterId = nil
        self.lastReadPageIndex = nil
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

    /// Updates the exact reading position.
    ///
    /// `pageIndex` is zero-based. The stored `readingProgress` is series-level:
    /// completed chapters count as whole units and the current chapter adds
    /// its own fraction. Reading the final page of the final chapter reaches
    /// `1.0`, while opening a chapter starts at that chapter's position in the
    /// series instead of showing the chapter as a fraction of the whole series.
    public func updateReadingPosition(chapterId: String, pageIndex: Int, totalPages: Int) {
        self.lastReadAt = Date()
        self.lastReadChapterId = chapterId
        self.lastReadPageIndex = pageIndex

        let chapterFraction: Double
        if totalPages > 0 {
            chapterFraction = Double(min(pageIndex + 1, totalPages)) / Double(totalPages)
        } else {
            chapterFraction = 0
        }

        let ordered = chaptersInReadingOrder
        if !ordered.isEmpty,
            let index = ordered.firstIndex(where: { $0.id == chapterId })
        {
            self.readingProgress = (Double(index) + chapterFraction) / Double(ordered.count)
        } else {
            self.readingProgress = chapterFraction
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
    public var isDownloaded: Bool
    public var downloadedAt: Date?
    public var downloadedPagesCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) public var manga: MangaEntity?
    @Relationship(deleteRule: .cascade, inverse: \PageEntity.chapter) public var pages: [PageEntity] = []
    @Relationship(deleteRule: .nullify, inverse: \ReadingProgressEntity.chapter) public var readingProgressEntries:
        [ReadingProgressEntity] = []
    @Relationship(deleteRule: .nullify, inverse: \BookmarkEntity.chapter) public var bookmarks: [BookmarkEntity] = []

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
        self.isDownloaded = false
        self.downloadedAt = nil
        self.downloadedPagesCount = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var isFullyDownloaded: Bool {
        isDownloaded && downloadedPagesCount >= pageCount && pageCount > 0
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
    public var fileSize: Int64?
    public var checksum: String?  // SHA-256 for integrity
    public var isDownloaded: Bool
    public var downloadedAt: Date?
    public var localPath: String?  // Local file path if downloaded
    public var createdAt: Date

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
        self.fileSize = nil
        self.checksum = nil
        self.isDownloaded = false
        self.downloadedAt = nil
        self.localPath = nil
        self.createdAt = Date()
    }
}

// MARK: - Reading Progress Entity

@Model
public final class ReadingProgressEntity {
    @Attribute(.unique) public var id: String
    public var pageIndex: Int
    public var totalPages: Int
    public var progress: Double  // 0.0 to 1.0
    public var readAt: Date
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
        timeSpent: TimeInterval = 0
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.totalPages = totalPages
        self.progress = totalPages > 0 ? Double(min(pageIndex + 1, totalPages)) / Double(totalPages) : 0.0
        self.readAt = Date()
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
    public var createdAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) public var manga: MangaEntity?
    @Relationship(deleteRule: .nullify) public var chapter: ChapterEntity?

    public init(
        id: String = UUID().uuidString,
        note: String? = nil,
        pageIndex: Int,
        manga: MangaEntity,
        chapter: ChapterEntity? = nil
    ) {
        self.id = id
        self.note = note
        self.pageIndex = pageIndex
        self.createdAt = Date()
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
