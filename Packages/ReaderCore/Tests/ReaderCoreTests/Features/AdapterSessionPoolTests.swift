// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class AdapterSessionPoolTests: XCTestCase {
    func testReusesSessionForTheSameProfile() async throws {
        let counter = RuntimeCounter()
        let store = TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")])
        let pool = AdapterSessionPool()
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")

        let first = try await acquire(pool: pool, profile: profile, store: store, counter: counter)
        XCTAssertEqual(counter.created, 1)
        first.release()

        let second = try await acquire(pool: pool, profile: profile, store: store, counter: counter)
        XCTAssertEqual(counter.created, 1)
        XCTAssertEqual(pool.cachedSessionCount, 1)
        second.release()
    }

    func testAdapterUpdateReplacesTheSession() async throws {
        let counter = RuntimeCounter()
        let store = TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")])
        let pool = AdapterSessionPool()
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")

        let first = try await acquire(pool: pool, profile: profile, store: store, counter: counter)
        first.release()

        store.bundles = [
            makeBundle(themeID: "theme.a", searchPath: "/search", version: "1.1.0")
        ]
        let second = try await acquire(pool: pool, profile: profile, store: store, counter: counter)

        XCTAssertEqual(counter.created, 2)
        await eventually { counter.disposed == 1 }
        second.release()
    }

    func testProfileEditReplacesTheSession() async throws {
        let counter = RuntimeCounter()
        let store = TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")])
        let pool = AdapterSessionPool()
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")

        let first = try await acquire(pool: pool, profile: profile, store: store, counter: counter)
        first.release()

        // Same id and adapter version, different network policy.
        let edited = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.com")
        let second = try await acquire(pool: pool, profile: edited, store: store, counter: counter)

        XCTAssertEqual(counter.created, 2)
        await eventually { counter.disposed == 1 }
        second.release()
    }

    func testUninstalledAdapterDropsTheCachedSession() async throws {
        let counter = RuntimeCounter()
        let store = TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")])
        let pool = AdapterSessionPool()
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")

        let first = try await acquire(pool: pool, profile: profile, store: store, counter: counter)
        first.release()
        store.bundles = []

        do {
            _ = try await pool.acquire(
                profile: profile,
                adapterStore: store,
                bridgeFactory: makeBridgeFactory(),
                runtimeFactory: { _, _ in counter.makeRuntime() }
            )
            XCTFail("Expected an adapterNotInstalled error")
        } catch let error as SiteBrowsingError {
            XCTAssertEqual(error, .adapterNotInstalled("theme.a"))
        }

        XCTAssertEqual(pool.cachedSessionCount, 0)
        await eventually { counter.disposed == 1 }
    }

    func testInvalidateAllDisposesEverySession() async throws {
        let counter = RuntimeCounter()
        let store = TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")])
        let pool = AdapterSessionPool()
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")

        let lease = try await acquire(pool: pool, profile: profile, store: store, counter: counter)
        lease.release()
        pool.invalidateAll()

        await eventually { counter.disposed == 1 }
        XCTAssertEqual(pool.cachedSessionCount, 0)
    }

    func testConcurrentAcquiresShareOneSession() async throws {
        let counter = RuntimeCounter()
        let store = TestAdapterStore(bundles: [makeBundle(themeID: "theme.a", searchPath: "/search")])
        let pool = AdapterSessionPool()
        let profile = makeProfile(id: "site-a", themeID: "theme.a", baseURL: "https://example.org")

        async let first = pool.acquire(
            profile: profile,
            adapterStore: store,
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in counter.makeRuntime() }
        )
        async let second = pool.acquire(
            profile: profile,
            adapterStore: store,
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in counter.makeRuntime() }
        )
        let leases = try await [first, second]
        for lease in leases {
            lease.release()
        }

        XCTAssertEqual(counter.created, 1)
    }

    // MARK: - Helpers

    private func acquire(
        pool: AdapterSessionPool,
        profile: SiteProfile,
        store: TestAdapterStore,
        counter: RuntimeCounter
    ) async throws -> AdapterSessionPool.Lease {
        try await pool.acquire(
            profile: profile,
            adapterStore: store,
            bridgeFactory: makeBridgeFactory(),
            runtimeFactory: { _, _ in counter.makeRuntime() }
        )
    }

    private func eventually(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition was not met before the timeout")
    }
}

// MARK: - Doubles

private final class RuntimeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var createdCount = 0
    private var disposedCount = 0

    var created: Int { lock.withLock { createdCount } }
    var disposed: Int { lock.withLock { disposedCount } }

    func makeRuntime() -> any SiteAdapterRuntime {
        lock.withLock { createdCount += 1 }
        return CountingRuntime(counter: self)
    }

    func markDisposed() {
        lock.withLock { disposedCount += 1 }
    }
}

private struct CountingRuntime: SiteAdapterRuntime {
    let counter: RuntimeCounter

    func search(
        _ query: SearchQuery,
        in page: PluginPageContext
    ) async throws -> PagedResult<MangaSummary> {
        PagedResult(items: [], hasNextPage: false)
    }

    func details(for key: String, in page: PluginPageContext) async throws -> MangaDetails {
        MangaDetails(key: key, title: "Lorem", status: .unknown, contentRating: .unknown)
    }

    func chapters(for key: String, in page: PluginPageContext) async throws -> [Chapter] { [] }
    func pages(
        mangaKey: String,
        chapterKey: String,
        in page: PluginPageContext
    ) async throws -> [Page] { [] }

    func extractGenres(
        mapping: GenreMapping,
        in page: PluginPageContext
    ) async throws -> ExtractedGenres { .init(filters: []) }

    func dispose() async {
        counter.markDisposed()
    }
}
