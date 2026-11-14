// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Minimal semantic-version value for adapter versions.
///
/// Adapters use `MAJOR.MINOR.PATCH` with an optional prerelease suffix. This
/// type exists so selection, downgrade checks and the settings UI share one
/// ordering instead of each comparing strings or `Double` components.
public struct AdapterVersion: Comparable, Sendable, CustomStringConvertible {
    private let raw: String
    private let components: [Int]
    private let prerelease: String?

    public init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        self.raw = trimmed
        self.components = parts[0].split(separator: ".").map { component in
            Int(component.prefix { $0.isNumber }) ?? 0
        }
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    public var description: String { raw }

    public static func < (lhs: AdapterVersion, rhs: AdapterVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }

        // A stable release sorts after every prerelease of the same version.
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case (let left?, let right?):
            return left < right
        }
    }

    public static func == (lhs: AdapterVersion, rhs: AdapterVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
