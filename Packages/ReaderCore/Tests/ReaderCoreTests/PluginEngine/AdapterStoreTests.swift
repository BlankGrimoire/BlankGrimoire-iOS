// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

@MainActor
final class AdapterStoreTests: XCTestCase {
    func testTrustRepositoryPreservesFetchedURL() async throws {
        let repository = TrustedRepository(
            url: "https://example.org/repository.json",
            name: "Synthetic repository",
            publicKey: "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )
        let entity = TrustedRepositoryEntity(trusted: repository)

        XCTAssertEqual(entity.url, "https://example.org/repository.json")
        XCTAssertEqual(entity.name, "Synthetic repository")
    }

    func testTrustRepositoryRejectsNonHTTPSURL() async throws {
        let store = try DefaultAdapterStore.createInMemory()
        let index = RepositoryIndex(
            formatVersion: 1,
            name: "Synthetic repository",
            publicKey: "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            extensions: []
        )

        do {
            try await store.trustRepository(index, from: "http://example.org/repository.json")
            XCTFail("Expected invalid repository URL")
        } catch let error as AdapterStoreError {
            XCTAssertEqual(error, .invalidRepositoryURL)
        }
    }

    func testTrustRepositoryThroughExistentialUsesCanonicalURL() async throws {
        let concrete = try DefaultAdapterStore.createInMemory()
        let store: any AdapterStore = concrete
        let index = RepositoryIndex(
            formatVersion: 1,
            name: "Synthetic repository",
            publicKey: "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            extensions: []
        )

        try await store.trustRepository(index, from: "example.org/repository.json")

        let trusted = try await store.listTrustedRepositories()
        XCTAssertEqual(trusted.count, 1)
        XCTAssertEqual(trusted.first?.url, "https://example.org/repository.json")
        XCTAssertEqual(trusted.first?.name, "Synthetic repository")
        let canonicalTrusted = try await store.isRepositoryTrusted("https://example.org/repository.json")
        let shorthandTrusted = try await store.isRepositoryTrusted("example.org/repository.json")
        let nameTrusted = try await store.isRepositoryTrusted("Synthetic repository")
        XCTAssertTrue(canonicalTrusted)
        XCTAssertTrue(shorthandTrusted)
        XCTAssertFalse(nameTrusted)
    }

    func testTrustRepositoryRejectsKeyChangeForSameURL() async throws {
        let store = try DefaultAdapterStore.createInMemory()
        let first = RepositoryIndex(
            formatVersion: 1,
            name: "Synthetic repository",
            publicKey: "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            extensions: []
        )
        let second = RepositoryIndex(
            formatVersion: 1,
            name: "Synthetic repository",
            publicKey: "ed25519:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
            extensions: []
        )

        try await store.trustRepository(first, from: "https://example.org/index.json")

        do {
            try await store.trustRepository(second, from: "https://example.org/index.json")
            XCTFail("Expected public key mismatch")
        } catch let error as AdapterStoreError {
            XCTAssertEqual(error, .publicKeyMismatch)
        }
    }

    func testPurgeRemovesLegacyNameIdentity() async throws {
        let store = try DefaultAdapterStore.createInMemory()
        let legacy = TrustedRepositoryEntity(
            trusted: TrustedRepository(
                url: "BlankGrimoire Themes",
                name: "BlankGrimoire Themes",
                publicKey: "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            )
        )
        let valid = TrustedRepositoryEntity(
            trusted: TrustedRepository(
                url: "https://example.org/index.json",
                name: "Example repository",
                publicKey: "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            )
        )
        try await store.insertTrustedRepositoryForTesting(legacy)
        try await store.insertTrustedRepositoryForTesting(valid)

        let removed = try store.purgeInvalidTrustedRepositories()

        XCTAssertEqual(removed, 1)
        let trusted = try await store.listTrustedRepositories()
        XCTAssertEqual(trusted.map(\.url), ["https://example.org/index.json"])
    }

    func testVersionComparisonRejectsDowngradeOrdering() {
        XCTAssertEqual(DefaultAdapterStore.compareVersions("1.0.10", "1.0.9"), .orderedDescending)
        XCTAssertEqual(DefaultAdapterStore.compareVersions("1.0.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(DefaultAdapterStore.compareVersions("1.0.0", "2.0.0"), .orderedAscending)
    }
}
