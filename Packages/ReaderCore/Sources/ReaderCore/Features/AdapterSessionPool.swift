// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Reuses open adapter sessions across operations.
///
/// Opening a session creates a `JSVirtualMachine` and evaluates the runtime and
/// the adapter. Doing that for every chapter page was the main cost reported in
/// SES-02, so sessions are kept per site profile and adapter version and
/// disposed after an idle period.
@MainActor
final class AdapterSessionPool {
    /// Identity of a cached session.
    ///
    /// The adapter version is part of the key: installing an update creates a
    /// new session and the old one is disposed instead of serving stale code.
    struct Key: Hashable {
        let profileID: String
        let themeID: String
        let adapterVersion: String
    }

    /// A borrowed session. Call ``release()`` when the operation finishes.
    ///
    /// Releasing never disposes the session: it stays warm for the next
    /// operation and is disposed when idle or when the adapter changes.
    @MainActor
    struct Lease {
        let session: AdapterSession
        private let key: Key
        private let pool: AdapterSessionPool

        init(session: AdapterSession, key: Key, pool: AdapterSessionPool) {
            self.session = session
            self.key = key
            self.pool = pool
        }

        func release() {
            pool.release(key)
        }
    }

    private struct Entry {
        let session: AdapterSession
        var inUse: Int
        var lastUsed: Date
    }

    /// Sessions idle for longer than this are closed.
    private let idleTTL: TimeInterval
    private var entries: [Key: Entry] = [:]
    private var openings: [Key: Task<Void, Error>] = [:]
    private var sweepTask: Task<Void, Never>?
    private var memoryWarningObserver: MemoryWarningObserver?

    init(idleTTL: TimeInterval = 10 * 60) {
        self.idleTTL = idleTTL
    }

    deinit {
        sweepTask?.cancel()
    }

    /// Returns a lease for `profile`, opening the adapter only when needed.
    func acquire(
        profile: SiteProfile,
        adapterStore: any AdapterStore,
        bridgeFactory: @escaping AdapterBridgeFactory = AdapterRuntimeDefaults.makeBridge,
        runtimeFactory: @escaping AdapterRuntimeFactory = AdapterRuntimeDefaults.makeRuntime
    ) async throws -> Lease {
        guard profile.hasValidBaseURL else {
            throw SiteBrowsingError.invalidSiteURL(profile.baseURL)
        }

        guard let bundle = try await adapterStore.getInstalledAdapter(id: profile.themeID) else {
            // A removed adapter must not keep serving from the pool.
            invalidate(profileID: profile.id)
            throw SiteBrowsingError.adapterNotInstalled(profile.themeID)
        }

        let key = Key(
            profileID: profile.id,
            themeID: profile.themeID,
            adapterVersion: bundle.version
        )

        // A profile can point at a new adapter version after an update: close
        // the old sessions instead of keeping dead JavaScript contexts around.
        evictEntries(for: profile.id, except: key)

        if let lease = use(key: key, profile: profile) {
            startSweepingIfNeeded()
            return lease
        }

        // A session with the same identity but a different configuration
        // (URL, headers, overrides) was disposed by `use`.
        if let opening = openings[key] {
            try await opening.value
        } else {
            let task = Task { @MainActor in
                do {
                    let session = try await AdapterSession.open(
                        profile: profile,
                        bundle: bundle,
                        bridgeFactory: bridgeFactory,
                        runtimeFactory: runtimeFactory
                    )
                    self.finishOpening(key: key, session: session)
                } catch {
                    self.openings[key] = nil
                    throw error
                }
            }
            openings[key] = task
            try await task.value
        }

        guard let lease = use(key: key, profile: profile) else {
            // The opening task completed but another caller already invalidated
            // the entry; retry once with fresh state.
            if let entry = entries[key] {
                entries[key] = nil
                await entry.session.dispose()
                return try await acquire(
                    profile: profile,
                    adapterStore: adapterStore,
                    bridgeFactory: bridgeFactory,
                    runtimeFactory: runtimeFactory
                )
            }
            throw SiteBrowsingError.adapterNotInstalled(profile.themeID)
        }

        startSweepingIfNeeded()
        return lease
    }

    /// Closes every session belonging to a profile.
    func invalidate(profileID: String) {
        evictEntries(for: profileID, except: nil)
    }

    /// Closes every pooled session, for example on a memory warning.
    func invalidateAll() {
        let sessions = entries.values.map(\.session)
        entries.removeAll()
        for session in sessions {
            Task { await session.dispose() }
        }
    }

    var cachedSessionCount: Int {
        entries.count
    }

    // MARK: - Private

    private func evictEntries(for profileID: String, except key: Key?) {
        let stale = entries.filter { $0.key.profileID == profileID && $0.key != key }
        for (staleKey, entry) in stale {
            entries[staleKey] = nil
            Task { await entry.session.dispose() }
        }
    }

    private func finishOpening(key: Key, session: AdapterSession) {
        openings[key] = nil
        entries[key] = Entry(session: session, inUse: 0, lastUsed: Date())
    }

    private func use(key: Key, profile: SiteProfile) -> Lease? {
        guard var entry = entries[key] else { return nil }

        guard entry.session.profile == profile else {
            // The user edited the profile (URL, headers, overrides): the
            // network policy and selector overrides inside the session are
            // stale, so close it and let the caller reopen.
            entries[key] = nil
            Task { await entry.session.dispose() }
            return nil
        }

        entry.inUse += 1
        entry.lastUsed = Date()
        entries[key] = entry
        return Lease(session: entry.session, key: key, pool: self)
    }

    fileprivate func release(_ key: Key) {
        guard var entry = entries[key] else { return }
        entry.inUse = max(0, entry.inUse - 1)
        entry.lastUsed = Date()
        entries[key] = entry
    }

    private func startSweepingIfNeeded() {
        if memoryWarningObserver == nil {
            memoryWarningObserver = MemoryWarningObserver { [weak self] in
                Task { @MainActor in
                    self?.invalidateAll()
                }
            }
        }

        guard sweepTask == nil else { return }
        let interval = max(5, min(idleTTL, 60))
        sweepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                self.evictIdleSessions()
            }
        }
    }

    private func evictIdleSessions() {
        let cutoff = Date().addingTimeInterval(-idleTTL)
        let idle = entries.filter { $0.value.inUse == 0 && $0.value.lastUsed < cutoff }
        for (key, entry) in idle {
            entries[key] = nil
            Task { await entry.session.dispose() }
        }
    }
}
