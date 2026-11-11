// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Cookies obtained by the visible verification browser, shared with the
/// plugin bridge.
///
/// The store is keyed by host and only ever returns cookies whose domain
/// matches the requested host, so one site cannot read another site's session.
/// Entries are memory-only: challenge cookies are short lived and must not be
/// written to disk.
public final class ChallengeCookieStore: @unchecked Sendable {
    public static let shared = ChallengeCookieStore()

    private let lock = NSLock()
    private var cookiesByHost: [String: [HTTPCookie]] = [:]

    init() {}

    /// Stores the cookies captured from a verification web view.
    public func store(_ cookies: [HTTPCookie], forHost host: String) {
        let host = Self.normalizedHost(host)
        guard !host.isEmpty, !cookies.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        var existing = cookiesByHost[host] ?? []
        var byKey = Dictionary(
            existing.map { (Self.key(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for cookie in cookies {
            byKey[Self.key(for: cookie)] = cookie
        }

        let now = Date()
        existing = byKey.values.filter { cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires > now
        }
        cookiesByHost[host] = existing
    }

    /// Returns the non-expired cookies that apply to a host.
    public func cookies(forHost host: String) -> [HTTPCookie] {
        let host = Self.normalizedHost(host)
        guard !host.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        return (cookiesByHost[host] ?? []).filter { cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires > now
        }
    }

    /// Removes every stored cookie. Used when a site profile is deleted.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        cookiesByHost.removeAll()
    }

    /// Removes the cookies stored for one host.
    public func removeCookies(forHost host: String) {
        let host = Self.normalizedHost(host)
        lock.lock()
        defer { lock.unlock() }
        cookiesByHost[host] = nil
    }

    private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func key(for cookie: HTTPCookie) -> String {
        "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
    }
}
