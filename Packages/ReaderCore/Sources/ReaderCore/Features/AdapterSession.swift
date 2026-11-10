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

/// Errors raised while opening or validating an adapter session.
public enum AdapterSessionError: Error, LocalizedError, Sendable, Equatable {
    case bundleIntegrityFailed(String)
    case invalidBundleEncoding
    case unsupportedAPIVersion(found: Int)

    public var errorDescription: String? {
        switch self {
        case .bundleIntegrityFailed(let detail):
            return "The installed adapter failed its integrity check: \(detail)"
        case .invalidBundleEncoding:
            return "The installed adapter is not valid UTF-8"
        case .unsupportedAPIVersion(let found):
            return "Unsupported adapter API version \(found); expected \(ContractVersion.current)"
        }
    }
}

typealias AdapterBridgeFactory = @Sendable (SiteProfile) -> PluginBridge
typealias AdapterRuntimeFactory = @Sendable (AdapterBundle, PluginBridge) throws -> any SiteAdapterRuntime

enum AdapterRuntimeDefaults {
    static func makeBridge(profile: SiteProfile) -> PluginBridge {
        PluginBridge(policy: profile.makeNetworkPolicy())
    }

    static func makeRuntime(bundle: AdapterBundle, bridge: PluginBridge) throws -> any SiteAdapterRuntime {
        // The bundle read from storage must still match the hash approved at
        // install time; otherwise a modified file would run unreviewed code.
        do {
            try SHA256Verifier.verify(bundle.bundleData, expectedHex: bundle.manifest.sha256)
        } catch {
            throw AdapterSessionError.bundleIntegrityFailed(error.localizedDescription)
        }

        guard let script = String(data: bundle.bundleData, encoding: .utf8) else {
            throw AdapterSessionError.invalidBundleEncoding
        }

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

        // Decoding validates this too, but an in-memory bundle could be built
        // without going through the decoder.
        guard bundle.manifest.apiVersion == ContractVersion.current else {
            throw AdapterSessionError.unsupportedAPIVersion(found: bundle.manifest.apiVersion)
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
