// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Abstraction used by the feature views to load image bytes.
///
/// The App target injects a `PipelineImageLoader` backed by IOS-7's
/// `ImagePipeline`; previews leave the dependency `nil` so they never touch the
/// network.
public protocol ImageLoading: Sendable {
    /// Loads image data for a URL, optionally sending per-request headers.
    ///
    /// Reader pages may require headers such as `Referer`; covers and favicons
    /// pass `nil`.
    func loadImageData(for url: String, headers: [String: String]?) async throws -> Data
    func clearCache() async
    /// Warms the cache for images the reader is likely to show next.
    func prefetch(_ urls: [String], headers: [String: [String: String]]) async
}

extension ImageLoading {
    /// Convenience overload for requests without custom headers.
    public func loadImageData(for url: String) async throws -> Data {
        try await loadImageData(for: url, headers: nil)
    }

    /// Prefetching is optional: previews and tests can ignore it.
    public func prefetch(_ urls: [String], headers: [String: [String: String]]) async {}
}

/// `ImageLoading` implementation backed by a lazily created `ImagePipeline`.
///
/// The pipeline is created on first use so the App composition root stays
/// synchronous. Creation is stored as a single task: concurrent first callers
/// await the same pipeline instead of each creating one and losing the shared
/// memory cache and request deduplication.
public actor PipelineImageLoader: ImageLoading {
    private var creationTask: Task<ImagePipeline, Error>?
    private var pipeline: ImagePipeline?
    private let configuration: ImagePipelineConfiguration

    public init(configuration: ImagePipelineConfiguration = ImagePipelineConfiguration()) {
        self.configuration = configuration
    }

    public func loadImageData(for url: String, headers: [String: String]?) async throws -> Data {
        try await resolvedPipeline().fetch(url, headers: headers).data
    }

    /// Clears the underlying memory and disk caches.
    ///
    /// This creates the pipeline when needed: the disk cache may hold files
    /// from a previous launch and must be cleared even if no image was loaded
    /// yet in this session.
    public func clearCache() async {
        guard let pipeline = try? await resolvedPipeline() else { return }
        await pipeline.clearCache()
    }

    public func prefetch(_ urls: [String], headers: [String: [String: String]]) async {
        guard let pipeline = try? await resolvedPipeline(), !urls.isEmpty else { return }
        _ = await pipeline.prefetch(urls, headers: headers, priority: .background)
    }

    private func resolvedPipeline() async throws -> ImagePipeline {
        if let pipeline {
            return pipeline
        }

        let task: Task<ImagePipeline, Error>
        if let creationTask {
            task = creationTask
        } else {
            let configuration = self.configuration
            task = Task.detached(priority: .userInitiated) {
                try await ImagePipeline.create(configuration: configuration)
            }
            creationTask = task
        }

        do {
            let created = try await task.value
            pipeline = created
            creationTask = nil
            return created
        } catch {
            creationTask = nil
            throw error
        }
    }
}
