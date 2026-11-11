// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

final class ImageCacheTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        try await super.tearDown()
    }

    func testMemoryCacheStoresAndRemovesData() async {
        let cache = MemoryImageCache(maxSize: 1024)

        await cache.setData(Data("image".utf8), for: "a")
        let stored = await cache.data(for: "a")
        XCTAssertEqual(stored, Data("image".utf8))

        await cache.removeData(for: "a")
        let removed = await cache.data(for: "a")
        XCTAssertNil(removed)
        let size = await cache.currentSize()
        XCTAssertEqual(size, 0)
    }

    func testMemoryCacheEvictsLeastRecentlyUsedEntry() async {
        let cache = MemoryImageCache(maxSize: 8)

        await cache.setData(Data("aaaa".utf8), for: "a")
        await cache.setData(Data("bbbb".utf8), for: "b")
        // Touch "a" so "b" becomes the least recently used entry.
        _ = await cache.data(for: "a")
        await cache.setData(Data("cccc".utf8), for: "c")

        let first = await cache.data(for: "a")
        let second = await cache.data(for: "b")
        let third = await cache.data(for: "c")
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertNotNil(third)
    }

    func testMemoryCacheDoesNotKeepEntryLargerThanLimit() async {
        let cache = MemoryImageCache(maxSize: 4)

        await cache.setData(Data("too large".utf8), for: "big")

        let stored = await cache.data(for: "big")
        let size = await cache.currentSize()
        XCTAssertNil(stored)
        XCTAssertEqual(size, 0)
    }

    func testDiskCachePersistsAcrossInstances() async throws {
        let directory = try makeTemporaryDirectory()
        let cache = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        await cache.setData(Data("image".utf8), for: "key")

        let reopened = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        let stored = await reopened.data(for: "key")
        XCTAssertEqual(stored, Data("image".utf8))
    }

    func testDiskCacheDropsEntryWhenFileIsMissing() async throws {
        let directory = try makeTemporaryDirectory()
        let cache = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        await cache.setData(Data("image".utf8), for: "key")

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "img" {
            try FileManager.default.removeItem(at: file)
        }

        let stored = await cache.data(for: "key")
        XCTAssertNil(stored)

        let reopened = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        let afterReopen = await reopened.data(for: "key")
        XCTAssertNil(afterReopen)
    }

    func testDiskCacheIndexDoesNotStoreSecrets() async throws {
        let directory = try makeTemporaryDirectory()
        let cache = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        await cache.setData(Data("image".utf8), for: "https://example.org/pages/1.jpg#digest")

        let indexURL = directory.appendingPathComponent("index.json")
        let index = try String(contentsOf: indexURL, encoding: .utf8)

        // JSONEncoder may escape slashes, so check the host fragment only.
        XCTAssertTrue(index.contains("example.org"))
        XCTAssertFalse(index.contains("Bearer"))
        XCTAssertFalse(index.contains("Authorization"))
    }

    func testDiskCacheLoadRemovesOrphanFiles() async throws {
        let directory = try makeTemporaryDirectory()
        let cache = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        await cache.setData(Data("image".utf8), for: "key")

        let orphan = directory.appendingPathComponent("orphan.img")
        try Data("orphan".utf8).write(to: orphan)

        _ = try await DiskImageCache.create(directory: directory, maxSize: 1024)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testDiskCacheLoadDropsEntriesWithMissingFiles() async throws {
        let directory = try makeTemporaryDirectory()
        let cache = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        await cache.setData(Data("image".utf8), for: "key")

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "img" {
            try FileManager.default.removeItem(at: file)
        }

        let reopened = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        let size = await reopened.currentSize()
        let stored = await reopened.data(for: "key")

        XCTAssertEqual(size, 0)
        XCTAssertNil(stored)
    }

    func testTieredCachePromotesDiskEntryToMemory() async throws {
        let directory = try makeTemporaryDirectory()
        let disk = try await DiskImageCache.create(directory: directory, maxSize: 1024)
        await disk.setData(Data("image".utf8), for: "key")

        let memory = MemoryImageCache(maxSize: 1024)
        let tiered = TieredImageCache(memoryCache: memory, diskCache: disk)

        let fetched = await tiered.data(for: "key")
        XCTAssertEqual(fetched, Data("image".utf8))

        let cachedInMemory = await memory.data(for: "key")
        XCTAssertEqual(cachedInMemory, Data("image".utf8))
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlankGrimoireImageCache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
