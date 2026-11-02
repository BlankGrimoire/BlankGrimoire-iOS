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
    public func makeEntity(manga: MangaEntity? = nil, pageCount: Int = 0) -> ChapterEntity {
        let entity = ChapterEntity(
            id: key,
            title: title,
            number: number,
            volume: volume,
            language: language,
            publishedAt: ContractDate.parse(publishedAt),
            group: group,
            pageCount: pageCount
        )
        entity.manga = manga
        return entity
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
    static func parse(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
