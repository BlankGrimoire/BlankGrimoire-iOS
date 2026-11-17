// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Where the reader starts when it opens a chapter.
public enum ReaderStartPosition: String, Sendable, Hashable, CaseIterable {
    /// Continue from the saved page.
    case restore
    /// Open the first page, even if the chapter was already finished.
    case beginning
    /// Open the last page, used when the series is already finished.
    case end
}

/// Rules for the position the reader opens a chapter at.
public enum ReaderEntryPoint {
    /// Start position for a chapter the user opened by tapping it.
    ///
    /// A finished chapter restarts from the beginning: the user chose to read
    /// it again. An unfinished chapter continues where it was left.
    public static func manualStart(for chapter: ChapterEntity) -> ReaderStartPosition {
        chapter.isRead ? .beginning : .restore
    }
}
