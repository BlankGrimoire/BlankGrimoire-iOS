// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation

/// Protocol for image caching.
public protocol ImageCache: Sendable {
    /// Returns the cached data for a key, or nil if not found.
    func data(for key: String) async -> Data?

    /// Stores data for a key.
    func setData(_ data: Data, for key: String) async

    /// Removes data for a key.
    func removeData(for key: String) async

    /// Clears all cached data.
    func clear() async

    /// Returns the current cache size in bytes.
    func currentSize() async -> UInt64

    /// Returns the maximum cache size in bytes.
    func maxSize() async -> UInt64
}

/// In-memory LRU image cache.
public actor MemoryImageCache: ImageCache {
    private final class Node {
        let key: String
        var data: Data
        var next: Node?
        weak var prev: Node?
        var accessCount: Int = 0
        var lastAccessed: Date = Date()

        init(key: String, data: Data) {
            self.key = key
            self.data = data
        }
    }

    private var head: Node?
    private var tail: Node?
    private var map: [String: Node] = [:]
    private var _currentSize: UInt64 = 0
    public let maxSize: UInt64

    public init(maxSize: UInt64 = 50 * 1024 * 1024) {  // 50 MB default
        self.maxSize = maxSize
    }

    public func currentSize() async -> UInt64 {
        _currentSize
    }

    public func maxSize() async -> UInt64 {
        maxSize
    }

    public func data(for key: String) async -> Data? {
        guard let node = map[key] else { return nil }

        // Update LRU
        node.lastAccessed = Date()
        node.accessCount += 1
        moveToHead(node)

        return node.data
    }

    public func setData(_ data: Data, for key: String) async {
        if let existing = map[key] {
            // Update existing
            let sizeDiff = Int64(data.count) - Int64(existing.data.count)
            _currentSize = UInt64(Int64(_currentSize) + sizeDiff)
            existing.data = data
            existing.lastAccessed = Date()
            existing.accessCount += 1
            moveToHead(existing)
        } else {
            // Add new
            let node = Node(key: key, data: data)
            map[key] = node
            addToHead(node)
            _currentSize += UInt64(data.count)
        }

        // Evict if over capacity
        await evictIfNeeded()
    }

    public func removeData(for key: String) async {
        guard let node = map.removeValue(forKey: key) else { return }
        _currentSize -= UInt64(node.data.count)
        removeNode(node)
    }

    public func clear() async {
        map.removeAll()
        head = nil
        tail = nil
        _currentSize = 0
    }

    // MARK: - LRU Helpers

    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil
        head?.prev = node
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func moveToHead(_ node: Node) {
        guard node !== head else { return }
        removeNode(node)
        addToHead(node)
    }

    private func removeNode(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if node === head { head = node.next }
        if node === tail { tail = node.prev }
        node.next = nil
        node.prev = nil
    }

    private func evictIfNeeded() async {
        while _currentSize > maxSize, let victim = tail {
            await removeData(for: victim.key)
        }
    }
}

/// Disk-based image cache with size limit.
public actor DiskImageCache: ImageCache {
    private let directory: URL
    private let maxSizeValue: UInt64
    private var _currentSize: UInt64 = 0
    private var index: [String: DiskCacheEntry] = [:]

    private struct DiskCacheEntry: Codable {
        let key: String
        let fileName: String
        let size: UInt64
        let lastAccessed: Date
        let createdAt: Date
    }

    private init(directory: URL, maxSize: UInt64) {
        self.directory = directory
        self.maxSizeValue = maxSize
    }

    /// Creates a new DiskImageCache asynchronously.
    public static func create(directory: URL, maxSize: UInt64 = 200 * 1024 * 1024) async throws -> DiskImageCache {
        let cache = DiskImageCache(directory: directory, maxSize: maxSize)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await cache.loadIndex()
        return cache
    }

    private func loadIndex() async {
        let indexURL = directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                let data = try Data(contentsOf: indexURL)
                let entries = try JSONDecoder().decode([DiskCacheEntry].self, from: data)
                for entry in entries {
                    index[entry.key] = entry
                    _currentSize += entry.size
                }
            } catch {
                // Ignore corrupted index
            }
        }
    }

    public func currentSize() async -> UInt64 {
        _currentSize
    }

    public func maxSize() async -> UInt64 {
        maxSizeValue
    }

    public func data(for key: String) async -> Data? {
        guard let entry = index[key] else { return nil }

        let fileURL = directory.appendingPathComponent(entry.fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            index.removeValue(forKey: key)
            await saveIndex()
            return nil
        }

        // Update access time
        index[key] = DiskCacheEntry(
            key: entry.key,
            fileName: entry.fileName,
            size: entry.size,
            lastAccessed: Date(),
            createdAt: entry.createdAt
        )
        await saveIndex()

        return try? Data(contentsOf: fileURL)
    }

    public func setData(_ data: Data, for key: String) async {
        let fileName = cacheKey(for: key) + ".img"
        let fileURL = directory.appendingPathComponent(fileName)

        // Remove old entry if exists
        if let oldEntry = index[key] {
            _currentSize -= oldEntry.size
            let oldURL = directory.appendingPathComponent(oldEntry.fileName)
            try? FileManager.default.removeItem(at: oldURL)
        }

        // Write new data
        do {
            try data.write(to: fileURL, options: .atomic)

            let entry = DiskCacheEntry(
                key: key,
                fileName: fileName,
                size: UInt64(data.count),
                lastAccessed: Date(),
                createdAt: Date()
            )

            _currentSize += entry.size
            index[key] = entry
            await saveIndex()

            // Evict if needed
            await evictIfNeeded()
        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public func removeData(for key: String) async {
        guard let entry = index.removeValue(forKey: key) else { return }
        _currentSize -= entry.size
        let fileURL = directory.appendingPathComponent(entry.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        await saveIndex()
    }

    public func clear() async {
        for entry in index.values {
            let fileURL = directory.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        index.removeAll()
        _currentSize = 0
        await saveIndex()
    }

    // MARK: - Helpers

    private func loadIndexSync() throws {
        let indexURL = directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            let entries = try JSONDecoder().decode([DiskCacheEntry].self, from: data)
            for entry in entries {
                index[entry.key] = entry
                _currentSize += entry.size
            }
        }
    }

    private func saveIndex() async {
        let entries = Array(index.values)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
        }
    }

    private func cacheKey(for key: String) -> String {
        let input = Data(key.utf8)
        let hash = SHA256.hash(data: input)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func evictIfNeeded() async {
        // Sort by last accessed (oldest first) and remove until under limit
        let sortedEntries = index.values.sorted { $0.lastAccessed < $1.lastAccessed }

        for entry in sortedEntries {
            if _currentSize <= maxSizeValue { break }
            await removeData(for: entry.key)
        }
    }
}

/// Combined two-tier cache (memory + disk).
public actor TieredImageCache: ImageCache {
    public let memoryCache: MemoryImageCache
    public let diskCache: DiskImageCache

    public init(
        memoryCache: MemoryImageCache = MemoryImageCache(),
        diskCache: DiskImageCache
    ) {
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }

    public func currentSize() async -> UInt64 {
        let memSize = await memoryCache.currentSize()
        let diskSize = await diskCache.currentSize()
        return memSize + diskSize
    }

    public func maxSize() async -> UInt64 {
        let memSize = await memoryCache.maxSize()
        let diskSize = await diskCache.maxSize()
        return memSize + diskSize
    }

    public func data(for key: String) async -> Data? {
        // Check memory first
        if let data = await memoryCache.data(for: key) {
            return data
        }

        // Check disk
        if let data = await diskCache.data(for: key) {
            // Promote to memory
            await memoryCache.setData(data, for: key)
            return data
        }

        return nil
    }

    public func setData(_ data: Data, for key: String) async {
        await memoryCache.setData(data, for: key)
        await diskCache.setData(data, for: key)
    }

    public func removeData(for key: String) async {
        await memoryCache.removeData(for: key)
        await diskCache.removeData(for: key)
    }

    public func clear() async {
        await memoryCache.clear()
        await diskCache.clear()
    }
}
