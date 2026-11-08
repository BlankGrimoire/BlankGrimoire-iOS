// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Adapter operations shared by site browsing and chapter page loading.
protocol SiteAdapterRuntime: Sendable {
    func search(_ query: SearchQuery, in page: PluginPageContext) async throws -> PagedResult<MangaSummary>
    func details(for key: String, in page: PluginPageContext) async throws -> MangaDetails
    func chapters(for key: String, in page: PluginPageContext) async throws -> [Chapter]
    func pages(mangaKey: String, chapterKey: String, in page: PluginPageContext) async throws -> [Page]
    func dispose() async
}

/// `SiteAdapterRuntime` backed by the JavaScript plugin runtime.
private struct JSAdapterRuntime: SiteAdapterRuntime {
    let runtime: JSPluginRuntime

    func search(_ query: SearchQuery, in page: PluginPageContext) async throws -> PagedResult<MangaSummary> {
        try await runtime.search(query, in: page)
    }

    func details(for key: String, in page: PluginPageContext) async throws -> MangaDetails {
        try await runtime.details(for: key, in: page)
    }

    func chapters(for key: String, in page: PluginPageContext) async throws -> [Chapter] {
        try await runtime.chapters(for: key, in: page)
    }

    func pages(mangaKey: String, chapterKey: String, in page: PluginPageContext) async throws -> [Page] {
        try await runtime.pages(mangaKey: mangaKey, chapterKey: chapterKey, in: page)
    }

    func dispose() async {
        await runtime.dispose()
    }
}

typealias AdapterBridgeFactory = @Sendable (SiteProfile) -> PluginBridge
typealias AdapterRuntimeFactory = @Sendable (AdapterBundle, PluginBridge) throws -> any SiteAdapterRuntime

enum AdapterRuntimeDefaults {
    static func makeBridge(profile: SiteProfile) -> PluginBridge {
        PluginBridge(policy: profile.makeNetworkPolicy())
    }

    static func makeRuntime(bundle: AdapterBundle, bridge: PluginBridge) throws -> any SiteAdapterRuntime {
        let script = String(decoding: bundle.bundleData, as: UTF8.self)
        let runtime = try JSPluginRuntime(
            runtimeScript: try PluginRuntimeResources.runtimeScript(),
            adapterScript: script,
            manifest: bundle.manifest,
            bridge: bridge
        )
        return JSAdapterRuntime(runtime: runtime)
    }
}

/// An open adapter runtime bound to one site profile.
@MainActor
struct AdapterSession {
    let profile: SiteProfile
    let bundle: AdapterBundle
    let bridge: PluginBridge
    let runtime: any SiteAdapterRuntime

    static func open(
        profile: SiteProfile,
        adapterStore: any AdapterStore,
        bridgeFactory: AdapterBridgeFactory = AdapterRuntimeDefaults.makeBridge,
        runtimeFactory: AdapterRuntimeFactory = AdapterRuntimeDefaults.makeRuntime
    ) async throws -> AdapterSession {
        guard let bundle = try await adapterStore.getInstalledAdapter(id: profile.themeID) else {
            throw SiteBrowsingError.adapterNotInstalled(profile.themeID)
        }

        let bridge = bridgeFactory(profile)
        do {
            let runtime = try runtimeFactory(bundle, bridge)
            return AdapterSession(profile: profile, bundle: bundle, bridge: bridge, runtime: runtime)
        } catch {
            bridge.dispose()
            throw error
        }
    }

    func dispose() async {
        await runtime.dispose()
        bridge.dispose()
    }

    /// Resolves a site-relative key into an absolute URL.
    static func absoluteURL(_ key: String, baseURL: String) -> URL? {
        if let url = URL(string: key), url.scheme != nil {
            return url
        }
        guard let base = URL(string: baseURL) else {
            return nil
        }
        return URL(string: key, relativeTo: base)?.absoluteURL
    }
}
