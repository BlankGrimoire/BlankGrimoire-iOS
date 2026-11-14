// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

@testable import ReaderCore

struct AdapterBundleInspectionTests {
    /// Mirrors the shape esbuild emits for a real adapter: a minified IIFE
    /// with a getter export, not a `{ default: ... }` object literal.
    private static let minifiedBundle = #"""
        "use strict";var BlankGrimoireRuntime=(()=>{var u={};Object.defineProperty(u,"default",{get:()=>f,enumerable:!0});var f={id:"theme.test",name:"Test Theme",version:"1.2.3",apiVersion:1,detectionSignature:{selectors:[".test"],minScore:7},selectors:{search:{path:"/search",item:".item",title:".title",link:"a"},details:{title:"h1"},chapters:{item:".chapter",link:"a",order:"desc"},pages:{strategies:[]}},referrerHeaders:{"cdn.example.org":"https://example.org/"}};return u})();
        """#

    @Test func readsMinifiedIIFEBundle() throws {
        let result = try DefaultAdapterStore.inspectBundle(
            Data(Self.minifiedBundle.utf8),
            sha256: "abc"
        )

        #expect(result.manifest.id == "theme.test")
        #expect(result.manifest.name == "Test Theme")
        #expect(result.manifest.version == "1.2.3")
        #expect(result.manifest.sha256 == "abc")
        #expect(result.manifest.detectionSignature.minScore == 7)
        #expect(result.selectors.search.link == "a")
        #expect(result.selectors.chapters.order == "desc")
        #expect(result.manifest.referrerHeaders == ["cdn.example.org": "https://example.org/"])
    }

    /// The map must survive the installed-adapter round trip, otherwise the
    /// app falls back to guessing the referrer at request time.
    @Test func preservesReferrerHeadersThroughInstalledEntity() {
        let headers = ["cdn.example.org": "https://example.org/"]
        let signature = ThemeSignature(minScore: 1)
        let selectors = ThemeSelectors(
            search: .init(path: "/search", item: ".item", title: ".title", link: "a"),
            details: .init(title: "h1"),
            chapters: .init(item: ".chapter", link: "a", order: "desc"),
            pages: .init(strategies: [])
        )
        let manifest = AdapterManifest(
            id: "theme.test",
            name: "Test Theme",
            version: "1.0.0",
            apiVersion: 1,
            detectionSignature: signature,
            sha256: "abc",
            referrerHeaders: headers
        )
        let adapter = ThemeAdapter(
            id: "theme.test",
            name: "Test Theme",
            version: "1.0.0",
            detectionSignature: signature,
            selectors: selectors,
            referrerHeaders: headers
        )
        let bundle = AdapterBundle(
            manifest: manifest,
            themeAdapter: adapter,
            bundleData: Data(Self.minifiedBundle.utf8),
            sourceRepositoryURL: "https://example.org/index.json"
        )

        let restored = InstalledAdapterEntity(bundle: bundle).toAdapterBundle()

        #expect(restored.themeAdapter.referrerHeaders == headers)
        #expect(restored.manifest.referrerHeaders == headers)
    }

    @Test func rejectsBundleWithoutRuntimeGlobal() {
        #expect(throws: AdapterStoreError.self) {
            try DefaultAdapterStore.inspectBundle(
                Data("var unrelated = {};".utf8),
                sha256: "abc"
            )
        }
    }
}
