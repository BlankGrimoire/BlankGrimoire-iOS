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

    /// Hosts allowed to serve images. Empty means "any public HTTPS host".
    public let allowedHosts: [String]

    /// Maximum accepted image size in bytes.
    public let maxImageBytes: Int

    public init(
        maxConcurrentDownloads: Int = 4,
        requestTimeout: TimeInterval = 30,
        enableDiskCache: Bool = true,
        memoryCacheSize: UInt64 = 50 * 1024 * 1024,  // 50 MB
        diskCacheSize: UInt64 = 200 * 1024 * 1024,  // 200 MB
        diskCacheDirectory: URL? = nil,
        defaultHeaders: [String: String] = [:],
        followRedirects: Bool = true,
        maxRedirects: Int = 5,
        allowedHosts: [String] = [],
        maxImageBytes: Int = 25 * 1024 * 1024
    ) {
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        self.requestTimeout = max(1, requestTimeout)
        self.enableDiskCache = enableDiskCache
        self.memoryCacheSize = memoryCacheSize
        self.diskCacheSize = diskCacheSize
        self.diskCacheDirectory =
            diskCacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(
                "ImagePipeline")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("ImagePipeline")
        self.defaultHeaders = defaultHeaders
        self.followRedirects = followRedirects
        self.maxRedirects = max(0, maxRedirects)
        self.allowedHosts = allowedHosts
        self.maxImageBytes = max(1, maxImageBytes)
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
        sessionConfig.httpCookieStorage = nil
        sessionConfig.httpShouldSetCookies = false
        sessionConfig.httpCookieAcceptPolicy = .never
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        let redirectGuard = ImageRedirectGuard(configuration: configuration)
        let session = URLSession(
            configuration: sessionConfig,
            delegate: redirectGuard,
            delegateQueue: nil
        )

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
    /// Deduplicates concurrent requests for the same URL. Requests with custom
    /// headers use a separate cache entry so credentialed pages never reuse the
    /// bytes cached for an unauthenticated request.
    ///
    /// - Parameters:
    ///   - url: The image URL to fetch.
    ///   - headers: Optional per-request headers (for example `Referer`).
    ///   - progress: Optional progress callback.
    /// - Returns: The image result.
    public func fetch(
        _ url: String,
        headers: [String: String]? = nil,
        progress: ImageProgressCallback? = nil
    ) async throws -> ImageResult {
        // Validate URL
        guard let url = URL(string: url) else {
            throw ImagePipelineError.invalidURL(url)
        }
        try validateImageURL(url)

        let cacheKey = cacheKey(for: url, headers: headers)

        // Check cache first
        if let cachedData = await cache.data(for: cacheKey) {
            logger.log("Cache hit: \(url.absoluteString)", level: .debug)
            return ImageResult(
                data: cachedData,
                mimeType: nil,
                fromCache: true,
                originalURL: url.absoluteString
            )
        }

        // Check if request is already in flight
        if let existing = inFlight[cacheKey] {
            logger.log("Deduplicating request: \(url.absoluteString)", level: .debug)
            return try await existing.task.value
        }

        // Create new request
        let task = Task {
            try await downloadAndCache(url, headers: headers, cacheKey: cacheKey, progress: progress)
        }

        inFlight[cacheKey] = InFlightRequest(task: task)
        defer { inFlight.removeValue(forKey: cacheKey) }

        return try await task.value
    }

    /// Fetches an image with a completion callback (for backward compatibility).
    public func fetch(
        _ url: String,
        headers: [String: String]? = nil,
        progress: ImageProgressCallback? = nil,
        completion: @escaping ImageCompletionCallback
    ) {
        Task {
            do {
                let result = try await fetch(url, headers: headers, progress: progress)
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
    ///   - headers: Optional headers keyed by URL.
    ///   - priority: Task priority.
    public func prefetch(
        _ urls: [String],
        headers: [String: [String: String]] = [:],
        priority: TaskPriority = .background
    ) async -> [String: Result<ImageResult, Error>] {
        var results: [String: Result<ImageResult, Error>] = [:]

        await withTaskGroup(of: (String, Result<ImageResult, Error>).self) { group in
            for url in urls {
                let urlHeaders = headers[url]
                group.addTask(priority: priority) {
                    do {
                        let result = try await self.fetch(url, headers: urlHeaders)
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
    ///
    /// - Parameters:
    ///   - pageURLs: Ordered page image URLs.
    ///   - count: How many leading pages to prefetch.
    ///   - headers: Optional headers keyed by URL. Passing the same headers used
    ///     by the reader keeps the cache key identical, avoiding a second
    ///     download with a different key.
    public func prefetchNextPages(
        _ pageURLs: [String],
        count: Int = 3,
        headers: [String: [String: String]] = [:]
    ) async {
        let urlsToPrefetch = Array(pageURLs.prefix(count))
        _ = await prefetch(urlsToPrefetch, headers: headers)
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

    private func downloadAndCache(
        _ url: URL,
        headers: [String: String]?,
        cacheKey: String,
        progress: ImageProgressCallback?
    ) async throws -> ImageResult {
        await semaphore.wait()
        defer { semaphore.signal() }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in headers ?? [:] where !Self.isReservedHeader(field) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        // Reuse cookies obtained by the visible verification browser.
        Self.applyChallengeCookies(to: &request, url: url)

        logger.log("Downloading: \(url.absoluteString)", level: .info)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImagePipelineError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ImagePipelineError.networkError("HTTP \(httpResponse.statusCode)")
        }

        if let expected = httpResponse.expectedContentLength as Int64?,
            expected > Int64(configuration.maxImageBytes)
        {
            throw ImagePipelineError.responseTooLarge(configuration.maxImageBytes)
        }

        let data = try await Self.collect(bytes, limit: configuration.maxImageBytes)
        try Self.validateImageData(data, mimeType: httpResponse.mimeType)

        // Cache the result
        await cache.setData(data, for: cacheKey)

        logger.log("Downloaded: \(url.absoluteString) (\(data.count) bytes)", level: .info)

        return ImageResult(
            data: data,
            mimeType: httpResponse.mimeType,
            fromCache: false,
            originalURL: url.absoluteString
        )
    }

    // MARK: - Request validation

    /// Only public HTTPS hosts may serve images.
    ///
    /// Adapters supply image URLs, so the pipeline cannot trust the scheme or
    /// the host: local files, loopback and private networks must be rejected.
    private func validateImageURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else {
            throw ImagePipelineError.invalidURL(url.absoluteString)
        }

        if !configuration.allowedHosts.isEmpty {
            let allowed = configuration.allowedHosts.contains { pattern in
                Self.host(host, matches: pattern)
            }
            guard allowed else {
                throw ImagePipelineError.hostNotAllowed(host)
            }
        }

        guard !Self.isPrivateHost(host) else {
            throw ImagePipelineError.hostNotAllowed(host)
        }
    }

    private static func host(_ host: String, matches pattern: String) -> Bool {
        let pattern = pattern.lowercased()
        guard !pattern.isEmpty else { return false }
        if pattern == host { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host == suffix || host.hasSuffix("." + suffix)
        }
        return host.hasSuffix("." + pattern)
    }

    /// Rejects loopback, link-local, private and single-label hosts.
    private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }

        if host.contains(":") {
            // IPv6 literal.
            return host == "::1" || host == "::" || host.hasPrefix("fe80:") || host.hasPrefix("fc")
                || host.hasPrefix("fd")
        }

        let parts = host.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else {
            // A public DNS name always has at least two labels.
            return !host.contains(".")
        }

        guard let first = UInt8(parts[0]), let second = UInt8(parts[1]) else { return true }
        if first == 10 || first == 127 || first == 0 || first == 169 && second == 254 {
            return true
        }
        if first == 192 && second == 168 {
            return true
        }
        if first == 172 && (16...31).contains(second) {
            return true
        }
        return false
    }

    private static func isReservedHeader(_ field: String) -> Bool {
        ["authorization", "cookie", "host"].contains(field.lowercased())
    }

    private static func applyChallengeCookies(to request: inout URLRequest, url: URL) {
        guard let host = url.host else { return }
        let cookies = ChallengeCookieStore.shared.cookies(forHost: host).filter { cookie in
            guard cookie.isSecure else { return false }
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host.lowercased() == domain || host.lowercased().hasSuffix("." + domain)
        }
        guard !cookies.isEmpty else { return }
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    /// Rejects HTML error pages masquerading as images.
    private static func validateImageData(_ data: Data, mimeType: String?) throws {
        guard !data.isEmpty else {
            throw ImagePipelineError.invalidResponse
        }

        if let mimeType = mimeType?.lowercased(), mimeType != "image/svg+xml" {
            guard mimeType.hasPrefix("image/") else {
                throw ImagePipelineError.unsupportedImageFormat
            }
        }

        let signature = [UInt8](data.prefix(12))
        guard Self.hasImageSignature(signature) else {
            throw ImagePipelineError.unsupportedImageFormat
        }
    }

    private static func hasImageSignature(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 4 else { return false }

        // JPEG
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        // PNG
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        // GIF87a / GIF89a
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }
        // BMP
        if bytes.starts(with: [0x42, 0x4D]) { return true }
        // TIFF (little/big endian)
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return true
        }
        // RIFF....WEBP
        if bytes.count >= 12, bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
            Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50]
        {
            return true
        }
        // ISO Base Media (HEIC/AVIF): ....ftyp
        if bytes.count >= 8, Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70] {
            return true
        }
        return false
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))
        for try await byte in bytes {
            if data.count >= limit {
                throw ImagePipelineError.responseTooLarge(limit)
            }
            data.append(byte)
        }
        return data
    }

    /// Cache keys include a stable hash of the custom headers.
    ///
    /// The URL alone would allow a credentialed request to serve its bytes to
    /// an unauthenticated one (and vice versa).
    private func cacheKey(for url: URL, headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else {
            return url.absoluteString
        }

        let canonical =
            headers
            .map { "\($0.key.lowercased()):\($0.value)" }
            .sorted()
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(url.absoluteString)#\(digest)"
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

// MARK: - Redirect guard

/// Applies the image network policy to every redirect hop.
///
/// `URLSession` follows redirects automatically by default, which would let a
/// public URL redirect to a private host or an insecure scheme. This delegate
/// re-validates each hop and enforces `maxRedirects`.
private final class ImageRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let configuration: ImagePipelineConfiguration
    private let lock = NSLock()
    private var redirectCounts: [Int: Int] = [:]

    init(configuration: ImagePipelineConfiguration) {
        self.configuration = configuration
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard configuration.followRedirects else {
            completionHandler(nil)
            return
        }

        guard let url = request.url,
            url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased(),
            !host.isEmpty,
            !Self.isPrivateHost(host)
        else {
            completionHandler(nil)
            return
        }

        if !configuration.allowedHosts.isEmpty {
            let allowed = configuration.allowedHosts.contains { pattern in
                Self.hostMatches(host, pattern: pattern)
            }
            guard allowed else {
                completionHandler(nil)
                return
            }
        }

        let redirects: Int = lock.withLock {
            let next = (redirectCounts[task.taskIdentifier] ?? 0) + 1
            redirectCounts[task.taskIdentifier] = next
            return next
        }
        guard redirects <= configuration.maxRedirects else {
            completionHandler(nil)
            return
        }

        var forwarded = request
        // Never forward credentials across hosts.
        if request.url?.host?.lowercased() != task.originalRequest?.url?.host?.lowercased() {
            forwarded.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(forwarded)
    }

    private static func hostMatches(_ host: String, pattern: String) -> Bool {
        let pattern = pattern.lowercased()
        guard !pattern.isEmpty else { return false }
        if pattern == host { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host == suffix || host.hasSuffix("." + suffix)
        }
        return host.hasSuffix("." + pattern)
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        if host.contains(":") {
            return host == "::1" || host == "::" || host.hasPrefix("fe80:") || host.hasPrefix("fc")
                || host.hasPrefix("fd")
        }
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else {
            return !host.contains(".")
        }
        guard let first = UInt8(parts[0]), let second = UInt8(parts[1]) else { return true }
        if first == 10 || first == 127 || first == 0 || (first == 169 && second == 254) {
            return true
        }
        if first == 192 && second == 168 { return true }
        if first == 172 && (16...31).contains(second) { return true }
        return false
    }
}

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
