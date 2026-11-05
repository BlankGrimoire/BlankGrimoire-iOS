// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Abstraction used by the feature views to load image bytes.
///
/// The App target injects a `PipelineImageLoader` backed by IOS-7's
/// `ImagePipeline`; previews leave the dependency `nil` so they never touch the
/// network.
public protocol ImageLoading: Sendable {
    func loadImageData(for url: String) async throws -> Data
}

/// `ImageLoading` implementation backed by a lazily created `ImagePipeline`.
///
/// The pipeline is created on first use so the App composition root stays
/// synchronous. It provides the memory/disk cache and request deduplication
/// implemented in IOS-7.
public actor PipelineImageLoader: ImageLoading {
    public static let shared = PipelineImageLoader()

    private var pipeline: ImagePipeline?
    private let configuration: ImagePipelineConfiguration

    public init(configuration: ImagePipelineConfiguration = ImagePipelineConfiguration()) {
        self.configuration = configuration
    }

    public func loadImageData(for url: String) async throws -> Data {
        try await resolvedPipeline().fetch(url).data
    }

    /// Clears the underlying memory and disk caches.
    public func clearCache() async {
        guard let pipeline else { return }
        await pipeline.clearCache()
    }

    private func resolvedPipeline() async throws -> ImagePipeline {
        if let pipeline {
            return pipeline
        }
        let created = try await ImagePipeline.create(configuration: configuration)
        pipeline = created
        return created
    }
}
