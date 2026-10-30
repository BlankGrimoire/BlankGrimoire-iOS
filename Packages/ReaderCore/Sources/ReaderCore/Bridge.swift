// SPDX-License-Identifier: MPL-2.0

import Foundation
import WebKit
import SwiftSoup

// MARK: - Native Bridge Protocol

/// The native bridge exposed to the JavaScript runtime.
/// All methods are called from the JS context via JSC bridge.
public protocol NativeBridge: Sendable {
    /// Perform an HTTP request
    func request(_ request: HttpRequest) async throws -> HttpResponse
    
    /// Parse HTML string into a document
    func parseHTML(_ html: String) async throws -> ParsedDocument
    
    /// Logging
    func log(_ message: String, _ level: Int, _ context: [String: Any]?)
    func error(_ message: String, _ level: Int, _ context: [String: Any]?)
    func warn(_ message: String, _ level: Int, _ context: [String: Any]?)
    
    /// Timer management
    func setTimeout(_ callback: @escaping @Sendable () -> Void, _ ms: Int) -> Int
    func clearTimeout(_ id: Int)
    
    /// Allowlist management
    func isAllowed(_ url: String) -> Bool
}

/// HTTP Request from adapter
public struct HttpRequest: Codable, Sendable {
    public let url: String
    public let method: String
    public let headers: [String: String]?
    public let body: String?
    
    public init(url: String, method: String = "GET", headers: [String: String]? = nil, body: String? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// HTTP Response to adapter
public struct HttpResponse: Codable, Sendable {
    public let status: Int
    public let url: String
    public let headers: [String: String]
    public let body: String
    
    public init(status: Int, url: String, headers: [String: String], body: String) {
        self.status = status
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// Parsed document returned to JS runtime
public struct ParsedDocument: Codable, Sendable {
    public let documentId: String
    public let title: String?
    public let url: String
    
    public init(documentId: String, title: String?, url: String) {
        self.documentId = documentId
        self.title = title
        self.url = url
    }
}

// MARK: - Document Selector (for JS queries)

/// Selector query from JS runtime
public struct SelectorQuery: Codable, Sendable {
    public let documentId: String
    public let selector: String
    public let multiple: Bool
    
    public init(documentId: String, selector: String, multiple: Bool = false) {
        self.documentId = documentId
        self.selector = selector
        self.multiple = multiple
    }
}

/// Element result from selector query
public struct ElementResult: Codable, Sendable {
    public let elementId: String
    public let tagName: String
    public let textContent: String?
    public let attributes: [String: String]
    public let outerHTML: String?
    
    public init(elementId: String, tagName: String, textContent: String?, attributes: [String: String], outerHTML: String?) {
        self.elementId = elementId
        self.tagName = tagName
        self.textContent = textContent
        self.attributes = attributes
        self.outerHTML = outerHTML
    }
}

// MARK: - JavaScript Value Types (for JSC bridge)

/// JSON value for bridge communication
public enum JSValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSValue])
    case object([String: JSValue])
    
    public init(_ value: Any?) {
        if value == nil || value is NSNull {
            self = .null
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let int = value as? Int {
            self = .int(int)
        } else if let double = value as? Double {
            self = .double(double)
        } else if let string = value as? String {
            self = .string(string)
        } else if let array = value as? [Any] {
            self = .array(array.map { JSValue($0) })
        } else if let dict = value as? [String: Any] {
            self = .object(dict.mapValues { JSValue($0) })
        } else {
            self = .string(String(describing: value))
        }
    }
    
    public func toAny() -> Any? {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { $0.toAny() }
        case .object(let o): return o.mapValues { $0.toAny() }
        }
    }
}

// MARK: - Timer Management

/// Timer handle for bridging JS timers
public final class TimerHandle: @unchecked Sendable {
    public let id: Int
    private let timer: Timer
    
    public init(id: Int, timer: Timer) {
        self.id = id
        self.timer = timer
    }
    
    public func invalidate() {
        timer.invalidate()
    }
}

// MARK: - Bridge Errors

public enum BridgeError: Error, LocalizedError, Sendable {
    case notAllowed(String)
    case invalidURL(String)
    case unsupportedProtocol(String)
    case networkError(String)
    case parseError(String)
    case documentNotFound(String)
    case elementNotFound(String)
    case timerNotFound(Int)
    case bridgeNotInitialized
    case jsExecutionError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAllowed(let url): return "Host not allowed by allowlist: \(url)"
        case .invalidURL(let url): return "Invalid request URL: \(url)"
        case .unsupportedProtocol(let proto): return "Unsupported protocol: \(proto)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .documentNotFound(let id): return "Document not found: \(id)"
        case .elementNotFound(let id): return "Element not found: \(id)"
        case .timerNotFound(let id): return "Timer not found: \(id)"
        case .bridgeNotInitialized: return "Bridge not initialized"
        case .jsExecutionError(let msg): return "JS execution error: \(msg)"
        }
    }
}