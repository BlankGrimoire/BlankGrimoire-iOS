// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Errors raised while loading or invoking a JavaScript theme adapter.
public enum PluginEngineError: Error, LocalizedError, Sendable, Equatable {
    case contextCreationFailed
    case runtimeResourceMissing
    case runtimeLoadFailed(String)
    case adapterLoadFailed(String)
    case invalidAdapter(String)
    case invalidManifest(String)
    case apiVersionMismatch(expected: Int, found: Int)
    case dispatchFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case requestNotConfigured
    case disposed
    case documentTooLarge(limit: Int)
    /// A site challenge (CAPTCHA, Turnstile, etc.) was encountered that requires user interaction.
    /// The associated URL is the challenge page that must be loaded in a visible WebView.
    case challengeRequired(URL)

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to create a JavaScriptCore context"
        case .runtimeResourceMissing:
            return "The vendored runtime.js resource is missing"
        case .runtimeLoadFailed(let message):
            return "Failed to load the JavaScript runtime: \(message)"
        case .adapterLoadFailed(let message):
            return "Failed to load the adapter bundle: \(message)"
        case .invalidAdapter(let message):
            return "Invalid adapter bundle: \(message)"
        case .invalidManifest(let message):
            return "Adapter manifest does not match the bundle: \(message)"
        case .apiVersionMismatch(let expected, let found):
            return "API version mismatch: expected \(expected), found \(found)"
        case .dispatchFailed(let message):
            return "Adapter dispatch failed: \(message)"
        case .encodingFailed(let message):
            return "Failed to encode a runtime argument: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode an adapter result: \(message)"
        case .requestNotConfigured:
            return "Native request handler is not configured"
        case .disposed:
            return "The JavaScript plugin runtime has been disposed"
        case .documentTooLarge(let limit):
            return "The parsed HTML document exceeds the \(limit)-byte limit"
        case .challengeRequired(let url):
            return "The site requires a verification before continuing: \(url.absoluteString)"
        }
    }
}
