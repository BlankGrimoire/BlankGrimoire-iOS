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
}
