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
        // An entry larger than the whole cache would evict everything and then
        // itself; reject it instead of thrashing the cache.
        guard UInt64(data.count) <= maxSize else {
            await removeData(for: key)
            return
        }

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
        let size = UInt64(node.data.count)
        _currentSize = _currentSize >= size ? _currentSize - size : 0
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

    private struct DiskCacheEntry: Codable, Sendable {
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
        let decoded: [DiskCacheEntry] = await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: indexURL.path),
                let data = try? Data(contentsOf: indexURL),
                let entries = try? JSONDecoder().decode([DiskCacheEntry].self, from: data)
            else {
                return []
            }
            return entries
        }.value

        // Reconcile the index with the files: entries whose file disappeared
        // are dropped instead of being served as misses forever.
        var knownFiles = Set<String>()
        for entry in decoded {
            let fileURL = directory.appendingPathComponent(entry.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            index[entry.key] = entry
            _currentSize += entry.size
            knownFiles.insert(entry.fileName)
        }

        // Remove orphan `.img` files left behind by earlier versions.
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        for file in files where file.pathExtension == "img" && !knownFiles.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }

        if knownFiles.count != decoded.count {
            await saveIndex()
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

        // The access time only feeds LRU eviction. Persisting it on every read
        // rewrote the whole index for each cache hit.
        index[key] = DiskCacheEntry(
            key: entry.key,
            fileName: entry.fileName,
            size: entry.size,
            lastAccessed: Date(),
            createdAt: entry.createdAt
        )

        let data: Data? = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return try? Data(contentsOf: fileURL)
        }.value

        guard let data else {
            // The file disappeared behind the index: drop the stale entry.
            index.removeValue(forKey: key)
            _currentSize = _currentSize >= entry.size ? _currentSize - entry.size : 0
            await saveIndex()
            return nil
        }
        return data
    }

    public func setData(_ data: Data, for key: String) async {
        let fileName = cacheKey(for: key) + ".img"
        let fileURL = directory.appendingPathComponent(fileName)

        // Remove the old entry *from the index* before touching the file. If
        // the write below fails, the index and the size counter stay
        // consistent, so a later eviction cannot subtract the same size twice.
        if let oldEntry = index.removeValue(forKey: key) {
            _currentSize = _currentSize >= oldEntry.size ? _currentSize - oldEntry.size : 0
            let oldURL = directory.appendingPathComponent(oldEntry.fileName)
            if oldEntry.fileName != fileName {
                try? FileManager.default.removeItem(at: oldURL)
            }
        }

        // Write new data off the actor: disk writes block whoever awaits them.
        let written = await Task.detached(priority: .utility) {
            (try? data.write(to: fileURL, options: .atomic)) != nil
        }.value

        guard written else {
            // Clean up on failure and persist the removal of the old entry.
            await Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: fileURL)
            }.value
            await saveIndex()
            return
        }

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
    }

    public func removeData(for key: String) async {
        guard let entry = index.removeValue(forKey: key) else { return }
        _currentSize = _currentSize >= entry.size ? _currentSize - entry.size : 0
        let fileURL = directory.appendingPathComponent(entry.fileName)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: fileURL)
        }.value
        await saveIndex()
    }

    public func clear() async {
        let files = index.values.map { directory.appendingPathComponent($0.fileName) }
        index.removeAll()
        _currentSize = 0
        await Task.detached(priority: .utility) {
            for fileURL in files {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }.value
        await saveIndex()
    }

    // MARK: - Helpers

    private func saveIndex() async {
        let entries = Array(index.values)
        let indexURL = directory.appendingPathComponent("index.json")
        await Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? data.write(to: indexURL, options: .atomic)
        }.value
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
