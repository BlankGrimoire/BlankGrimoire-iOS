// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation

/// Configuration for the image pipeline.
public struct ImagePipelineConfiguration: Sendable {
    /// Maximum number of concurrent downloads.
    public let maxConcurrentDownloads: Int

    /// Request timeout in seconds.
    public let requestTimeout: TimeInterval

    /// Whether to enable disk caching.
    public let enableDiskCache: Bool

    /// Memory cache size limit in bytes.
    public let memoryCacheSize: UInt64

    /// Disk cache size limit in bytes.
    public let diskCacheSize: UInt64

    /// Disk cache directory.
    public let diskCacheDirectory: URL

    /// Default headers to include in requests.
    public let defaultHeaders: [String: String]

    /// Whether to follow redirects.
    public let followRedirects: Bool

    /// Maximum number of redirects to follow.
    public let maxRedirects: Int

    public init(
        maxConcurrentDownloads: Int = 4,
        requestTimeout: TimeInterval = 30,
        enableDiskCache: Bool = true,
        memoryCacheSize: UInt64 = 50 * 1024 * 1024,  // 50 MB
        diskCacheSize: UInt64 = 200 * 1024 * 1024,  // 200 MB
        diskCacheDirectory: URL? = nil,
        defaultHeaders: [String: String] = [:],
        followRedirects: Bool = true,
        maxRedirects: Int = 5
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.requestTimeout = requestTimeout
        self.enableDiskCache = enableDiskCache
        self.memoryCacheSize = memoryCacheSize
        self.diskCacheSize = diskCacheSize
        self.diskCacheDirectory =
            diskCacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(
                "ImagePipeline")
        self.defaultHeaders = defaultHeaders
        self.followRedirects = followRedirects
        self.maxRedirects = maxRedirects
    }
}

/// Progress callback for image downloads.
public typealias ImageProgressCallback = @Sendable (Int64, Int64?) -> Void

/// Completion callback for image downloads.
public typealias ImageCompletionCallback = @Sendable (Result<ImageResult, Error>) -> Void

/// Main image pipeline actor.
///
/// Handles image downloading with:
/// - Deduplicated in-flight requests
/// - Bounded concurrency
/// - Two-tier caching (memory + disk)
/// - Progress reporting
/// - Cancellation support
public actor ImagePipeline {
    public let configuration: ImagePipelineConfiguration

    private let cache: any ImageCache
    private let session: URLSession
    private let semaphore: AsyncSemaphore
    private var inFlight: [String: InFlightRequest] = [:]
    private let logger: ImagePipelineLogger

    private init(
        configuration: ImagePipelineConfiguration,
        cache: any ImageCache,
        session: URLSession,
        semaphore: AsyncSemaphore,
        logger: ImagePipelineLogger
    ) {
        self.configuration = configuration
        self.cache = cache
        self.session = session
        self.semaphore = semaphore
        self.logger = logger
    }

    /// Creates a new ImagePipeline asynchronously.
    public static func create(
        configuration: ImagePipelineConfiguration = ImagePipelineConfiguration(),
        providedCache: (any ImageCache)? = nil,
        logger: ImagePipelineLogger = DefaultImagePipelineLogger()
    ) async throws -> ImagePipeline {
        let semaphore = AsyncSemaphore(value: configuration.maxConcurrentDownloads)
        let logger = logger

        // Create cache
        let cache: any ImageCache
        if let providedCache = providedCache {
            cache = providedCache
        } else if configuration.enableDiskCache {
            let memoryCache = MemoryImageCache(maxSize: configuration.memoryCacheSize)
            let diskCache = try await DiskImageCache.create(
                directory: configuration.diskCacheDirectory,
                maxSize: configuration.diskCacheSize
            )
            let tieredCache = TieredImageCache(memoryCache: memoryCache, diskCache: diskCache)
            cache = tieredCache
        } else {
            cache = MemoryImageCache(maxSize: configuration.memoryCacheSize)
        }

        // Configure URLSession
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.requestTimeout * 2
        sessionConfig.httpAdditionalHeaders = configuration.defaultHeaders
        sessionConfig.httpShouldSetCookies = false
        sessionConfig.httpCookieAcceptPolicy = .never
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: sessionConfig)

        return ImagePipeline(
            configuration: configuration,
            cache: cache,
            session: session,
            semaphore: semaphore,
            logger: logger
        )
    }

    /// Fetches an image from a URL.
    ///
    /// Deduplicates concurrent requests for the same URL.
    /// Returns cached data immediately if available.
    ///
    /// - Parameters:
    ///   - url: The image URL to fetch.
    ///   - progress: Optional progress callback.
    /// - Returns: The image result.
    public func fetch(
        _ url: String,
        progress: ImageProgressCallback? = nil
    ) async throws -> ImageResult {
        // Validate URL
        guard let url = URL(string: url) else {
            throw ImagePipelineError.invalidURL(url)
        }

        // Check cache first
        if let cachedData = await cache.data(for: url.absoluteString) {
            logger.log("Cache hit: \(url.absoluteString)", level: .debug)
            return ImageResult(
                data: cachedData,
                mimeType: nil,
                fromCache: true,
                originalURL: url.absoluteString
            )
        }

        // Check if request is already in flight
        if let existing = inFlight[url.absoluteString] {
            logger.log("Deduplicating request: \(url.absoluteString)", level: .debug)
            return try await existing.task.value
        }

        // Create new request
        let task = Task {
            try await downloadAndCache(url, progress: progress)
        }

        inFlight[url.absoluteString] = InFlightRequest(task: task)
        defer { inFlight.removeValue(forKey: url.absoluteString) }

        return try await task.value
    }

    /// Fetches an image with a completion callback (for backward compatibility).
    public func fetch(
        _ url: String,
        progress: ImageProgressCallback? = nil,
        completion: @escaping ImageCompletionCallback
    ) {
        Task {
            do {
                let result = try await fetch(url, progress: progress)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Prefetches images for a list of URLs.
    ///
    /// Downloads images in the background without blocking.
    /// Useful for prefetching next pages in a chapter.
    ///
    /// - Parameters:
    ///   - urls: URLs to prefetch.
    ///   - priority: Task priority.
    ///   - completion: Called when all prefetches complete.
    public func prefetch(
        _ urls: [String],
        priority: TaskPriority = .background
    ) async -> [String: Result<ImageResult, Error>] {
        var results: [String: Result<ImageResult, Error>] = [:]

        await withTaskGroup(of: (String, Result<ImageResult, Error>).self) { group in
            for url in urls {
                group.addTask(priority: priority) {
                    do {
                        let result = try await self.fetch(url)
                        return (url, .success(result))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }

            for await (url, result) in group {
                results[url] = result
            }
        }

        return results
    }

    /// Prefetches images for the next N pages of a chapter.
    public func prefetchNextPages(
        _ pageURLs: [String],
        count: Int = 3
    ) async {
        let urlsToPrefetch = Array(pageURLs.prefix(count))
        _ = await prefetch(urlsToPrefetch)
    }

    /// Clears all caches.
    public func clearCache() async {
        await cache.clear()
    }

    /// Returns current cache statistics.
    public func cacheStatistics() async -> CacheStatistics {
        var memorySize = await cache.currentSize()
        let diskSize: UInt64

        if let tieredCache = cache as? TieredImageCache {
            memorySize = await tieredCache.memoryCache.currentSize()
            diskSize = await tieredCache.diskCache.currentSize()
        } else if let memoryCache = cache as? MemoryImageCache {
            memorySize = await memoryCache.currentSize()
            diskSize = 0
        } else if let diskCache = cache as? DiskImageCache {
            memorySize = 0
            diskSize = await diskCache.currentSize()
        } else {
            memorySize = 0
            diskSize = 0
        }

        return CacheStatistics(
            memoryCacheSize: memorySize,
            diskCacheSize: diskSize,
            totalSize: memorySize + diskSize,
            inFlightRequests: inFlight.count
        )
    }

    // MARK: - Private

    private func downloadAndCache(_ url: URL, progress: ImageProgressCallback?) async throws -> ImageResult {
        await semaphore.wait()
        defer { semaphore.signal() }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        logger.log("Downloading: \(url.absoluteString)", level: .info)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImagePipelineError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ImagePipelineError.networkError("HTTP \(httpResponse.statusCode)")
        }

        // Determine MIME type
        let mimeType = httpResponse.mimeType

        // Cache the result
        await cache.setData(data, for: url.absoluteString)

        logger.log("Downloaded: \(url.absoluteString) (\(data.count) bytes)", level: .info)

        return ImageResult(
            data: data,
            mimeType: mimeType,
            fromCache: false,
            originalURL: url.absoluteString
        )
    }

    // MARK: - Private properties

    private struct InFlightRequest {
        let task: Task<ImageResult, Error>
        var subscribers: [ImageCompletionCallback] = []
    }

    // MARK: - Private methods

    private func log(_ message: String, level: LogLevel) {
        logger.log(message, level: level)
    }
}

// MARK: - Cache Statistics

/// Statistics about cache usage.
// MARK: - Async Semaphore

/// A simple async semaphore implementation using a lock for synchronization.
/// This is not an actor to allow synchronous signal() calls from defer blocks.
private final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        let shouldWait: Bool = lock.withLock {
            if value > 0 {
                value -= 1
                return false
            }
            return true
        }

        if shouldWait {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    waiters.append(continuation)
                }
            }
        }
    }

    func signal() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            if let waiter = waiters.popLast() {
                return waiter
            } else {
                value += 1
                return nil
            }
        }
        continuation?.resume()
    }
}

// MARK: - Logger

/// Logger protocol for image pipeline.
public protocol ImagePipelineLogger: Sendable {
    func log(_ message: String, level: LogLevel)
}

public enum LogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

public struct DefaultImagePipelineLogger: ImagePipelineLogger {
    public init() {}
    public func log(_ message: String, level: LogLevel) {
        let prefix: String
        switch level {
        case .debug: prefix = "🔍"
        case .info: prefix = "ℹ️"
        case .warning: prefix = "⚠️"
        case .error: prefix = "❌"
        }
        print("\(prefix) [ImagePipeline] \(message)")
    }
}

// MARK: - Cache Statistics

/// Statistics about cache usage.
public struct CacheStatistics: Sendable, Equatable {
    public let memoryCacheSize: UInt64
    public let diskCacheSize: UInt64
    public let totalSize: UInt64
    public let inFlightRequests: Int

    public init(
        memoryCacheSize: UInt64,
        diskCacheSize: UInt64,
        totalSize: UInt64,
        inFlightRequests: Int
    ) {
        self.memoryCacheSize = memoryCacheSize
        self.diskCacheSize = diskCacheSize
        self.totalSize = totalSize
        self.inFlightRequests = inFlightRequests
    }
}

// MARK: - Async Semaphore
