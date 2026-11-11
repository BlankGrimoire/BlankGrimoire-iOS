// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Errors that can occur during image pipeline operations.
public enum ImagePipelineError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case networkError(String)
    case invalidResponse
    case unsupportedImageFormat
    case decodingFailed(String)
    case cacheWriteFailed(String)
    case cacheReadFailed(String)
    case cancelled
    case timeout
    case diskSpaceExhausted
    case invalidCacheConfiguration
    case hostNotAllowed(String)
    case responseTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid image URL: \(url)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidResponse:
            return "Invalid HTTP response"
        case .unsupportedImageFormat:
            return "Unsupported image format"
        case .decodingFailed(let msg):
            return "Image decoding failed: \(msg)"
        case .cacheWriteFailed(let msg):
            return "Cache write failed: \(msg)"
        case .cacheReadFailed(let msg):
            return "Cache read failed: \(msg)"
        case .cancelled:
            return "Request was cancelled"
        case .timeout:
            return "Request timed out"
        case .diskSpaceExhausted:
            return "Disk space exhausted"
        case .invalidCacheConfiguration:
            return "Invalid cache configuration"
        case .hostNotAllowed(let host):
            return "Image host is not allowed: \(host)"
        case .responseTooLarge(let limit):
            return "Image exceeds the \(limit)-byte limit"
        }
    }
}

/// Result of an image request.
public struct ImageResult: Sendable, Equatable {
    public let data: Data
    public let mimeType: String?
    public let fromCache: Bool
    public let originalURL: String

    public init(data: Data, mimeType: String?, fromCache: Bool, originalURL: String) {
        self.data = data
        self.mimeType = mimeType
        self.fromCache = fromCache
        self.originalURL = originalURL
    }
}
