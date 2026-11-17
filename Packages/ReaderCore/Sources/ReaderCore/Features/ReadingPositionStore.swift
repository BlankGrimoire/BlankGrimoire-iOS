// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Remembers how far into a page the reader stopped.
///
/// This is reader view state, not library data: it only matters for reopening
/// a chapter at the same spot. Keeping it out of the SwiftData store avoids a
/// schema migration for a value that changes on every scroll burst.
public struct ReadingPositionStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Saved page and in-page offset for a chapter.
    public func position(mangaID: String, chapterID: String) -> (pageIndex: Int, offset: Double)? {
        guard
            let raw = defaults.dictionary(forKey: key(mangaID: mangaID, chapterID: chapterID)),
            let page = raw["page"] as? Double,
            let offset = raw["offset"] as? Double
        else { return nil }

        return (Int(page), min(max(offset, 0), 1))
    }

    public func setPosition(
        pageIndex: Int,
        offset: Double,
        mangaID: String,
        chapterID: String
    ) {
        defaults.set(
            ["page": Double(pageIndex), "offset": min(max(offset, 0), 1)],
            forKey: key(mangaID: mangaID, chapterID: chapterID)
        )
    }

    public func removePosition(mangaID: String, chapterID: String) {
        defaults.removeObject(forKey: key(mangaID: mangaID, chapterID: chapterID))
    }

    private func key(mangaID: String, chapterID: String) -> String {
        "reader.position.\(mangaID)::\(chapterID)"
    }
}
