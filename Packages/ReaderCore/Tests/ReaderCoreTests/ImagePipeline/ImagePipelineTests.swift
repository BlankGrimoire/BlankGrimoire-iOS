// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

final class ImagePipelineTests: XCTestCase {

    private func makePipeline(
        allowedHosts: [String] = [],
        cache: (any ImageCache)? = nil
    ) async throws -> ImagePipeline {
        let configuration = ImagePipelineConfiguration(
            enableDiskCache: false,
            memoryCacheSize: 1024 * 1024,
            allowedHosts: allowedHosts
        )
        return try await ImagePipeline.create(
            configuration: configuration,
            providedCache: cache ?? MemoryImageCache(maxSize: configuration.memoryCacheSize)
        )
    }

    func testFetchRejectsInsecureScheme() async throws {
        let pipeline = try await makePipeline()

        do {
            _ = try await pipeline.fetch("http://example.org/image.jpg")
            XCTFail("Expected invalidURL")
        } catch let error as ImagePipelineError {
            guard case .invalidURL = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testFetchRejectsHostsOutsideAllowlist() async throws {
        let pipeline = try await makePipeline(allowedHosts: ["cdn.example.org"])

        do {
            _ = try await pipeline.fetch("https://example.com/image.jpg")
            XCTFail("Expected hostNotAllowed")
        } catch let error as ImagePipelineError {
            guard case .hostNotAllowed(let host) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(host, "example.com")
        }
    }

    func testFetchRejectsPrivateAndLoopbackHosts() async throws {
        let pipeline = try await makePipeline()

        for url in [
            "https://localhost/image.jpg",
            "https://127.0.0.1/image.jpg",
            "https://192.168.1.10/image.jpg",
            "https://10.0.0.1/image.jpg",
            "https://service.local/image.jpg",
        ] {
            do {
                _ = try await pipeline.fetch(url)
                XCTFail("Expected hostNotAllowed for \(url)")
            } catch let error as ImagePipelineError {
                guard case .hostNotAllowed = error else {
                    return XCTFail("Unexpected error for \(url): \(error)")
                }
            }
        }
    }

    func testFetchReturnsCachedDataWithoutNetwork() async throws {
        let cache = MemoryImageCache(maxSize: 1024 * 1024)
        let url = "https://cdn.example.org/image.png"
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        await cache.setData(data, for: url)

        let pipeline = try await makePipeline(allowedHosts: ["cdn.example.org"], cache: cache)
        let result = try await pipeline.fetch(url)

        XCTAssertTrue(result.fromCache)
        XCTAssertEqual(result.data, data)
        XCTAssertEqual(result.originalURL, url)
    }

    func testCacheKeyHashesSensitiveHeaders() async throws {
        let pipeline = try await makePipeline(allowedHosts: ["cdn.example.org"])
        let url = try XCTUnwrap(URL(string: "https://cdn.example.org/image.png"))

        let plain = await pipeline.cacheKey(for: url, headers: nil)
        let credentialed = await pipeline.cacheKey(
            for: url,
            headers: ["Authorization": "Bearer super-secret-token"]
        )

        XCTAssertNotEqual(plain, credentialed)
        XCTAssertFalse(credentialed.contains("super-secret-token"))
        XCTAssertFalse(credentialed.contains("Authorization"))

        let reordered = await pipeline.cacheKey(
            for: url,
            headers: ["authorization": "Bearer super-secret-token"]
        )
        XCTAssertEqual(credentialed, reordered)
    }

    func testCacheStatisticsDistinguishTiers() async throws {
        let cache = MemoryImageCache(maxSize: 1024)
        await cache.setData(Data("image".utf8), for: "key")

        let pipeline = try await makePipeline(cache: cache)
        let statistics = await pipeline.cacheStatistics()

        XCTAssertEqual(statistics.memoryCacheSize, 5)
        XCTAssertEqual(statistics.diskCacheSize, 0)
        XCTAssertEqual(statistics.totalSize, 5)
        XCTAssertEqual(statistics.inFlightRequests, 0)
    }
}
