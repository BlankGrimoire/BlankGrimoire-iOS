// SPDX-License-Identifier: MPL-2.0

import Foundation

// DTOs are the only contract values returned by the JavaScript runtime. These
// helpers keep SwiftData models out of the engine and make the DTO -> entity
// conversion explicit for the persistence and feature layers.

@MainActor
extension MangaSummary {
    /// Builds a partial library entry from a search result.
    public func makeEntity(isFavorite: Bool = false) -> MangaEntity {
        MangaEntity(
            id: key,
            title: title,
            coverURL: coverURL,
            isFavorite: isFavorite
        )
    }
}

@MainActor
extension MangaDetails {
    /// Builds a complete library entry from series details.
    public func makeEntity(isFavorite: Bool = false) -> MangaEntity {
        MangaEntity(
            id: key,
            title: title,
            coverURL: coverURL,
            altTitles: altTitles ?? [],
            authors: authors ?? [],
            artists: artists ?? [],
            synopsis: synopsis,
            tags: tags ?? [],
            status: status,
            contentRating: contentRating,
            isFavorite: isFavorite
        )
    }

    /// Refreshes an existing library entry without replacing its local state.
    public func apply(to entity: MangaEntity) {
        entity.title = title
        entity.coverURL = coverURL
        entity.altTitles = altTitles ?? []
        entity.authors = authors ?? []
        entity.artists = artists ?? []
        entity.synopsis = synopsis
        entity.tags = tags ?? []
        entity.status = status
        entity.contentRating = contentRating
        entity.updatedAt = Date()
    }
}

@MainActor
extension Chapter {
    /// Builds a chapter entity, optionally attached to its manga.
    ///
    /// When `siteProfileID` is provided, the identifier is scoped to the site
    /// profile so two sites cannot collide on the same adapter key.
    public func makeEntity(
        manga: MangaEntity? = nil,
        pageCount: Int = 0,
        siteProfileID: String? = nil
    ) -> ChapterEntity {
        let identifier =
            siteProfileID.map { "\($0)::\(key)" }
            ?? key
        let entity = ChapterEntity(
            id: identifier,
            sourceKey: siteProfileID == nil ? nil : key,
            pageCount: pageCount
        )
        apply(to: entity, manga: manga)
        return entity
    }

    /// Refreshes an existing chapter without discarding its local state.
    ///
    /// `pageCount`, download status and reading progress stay untouched.
    public func apply(to entity: ChapterEntity, manga: MangaEntity? = nil) {
        entity.title = title
        entity.number = number
        entity.volume = volume
        entity.language = language
        entity.publishedAt = ContractDate.parse(publishedAt)
        entity.group = group
        if let manga {
            entity.manga = manga
        }
        entity.updatedAt = Date()
    }
}

@MainActor
extension Page {
    /// Builds a page entity, optionally attached to its chapter.
    public func makeEntity(chapter: ChapterEntity? = nil) -> PageEntity {
        let entity = PageEntity(
            index: index,
            imageURL: imageURL,
            headers: headers
        )
        entity.chapter = chapter
        return entity
    }
}

private enum ContractDate {
    // Formatters are immutable after creation, so sharing them is safe and
    // avoids allocating one for every parsed date.
    nonisolated(unsafe) private static let fractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        return fractionalSeconds.date(from: value) ?? wholeSeconds.date(from: value)
    }
}
