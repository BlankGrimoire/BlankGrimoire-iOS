// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftSoup
import WebKit

// MARK: - Native Bridge Implementation

/// Thread-safe native bridge implementation
public final class NativeBridgeImpl: NativeBridge, @unchecked Sendable {
    // Allowlist - supports exact hosts and wildcard subdomains (e.g., "*.example.org")
    private var allowedHosts: Set<String> = []
    private let allowlistLock = NSLock()
    
    // Document storage
    private var documents: [String: Document] = [:]
    private let documentQueue = DispatchQueue(label: "com.blankgrimoire.documents", attributes: .concurrent)
    
    // Element storage
    private var elements: [String: Element] = [:]
    private let elementQueue = DispatchQueue(label: "com.blankgrimoire.elements", attributes: .concurrent)
    
    // Timers
    private var timers: [Int: TimerHandle] = [:]
    private var timerCounter = 0
    private let timerQueue = DispatchQueue(label: "com.blankgrimoire.timers")
    
    // Network
    private let session: URLSession
    private let maxRedirects = 5
    
    // Logging
    private let logger: Logger
    
    public init(allowedHosts: [String] = [], logger: Logger = Logger()) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        self.logger = logger
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Allowlist
    
    /// Check if a URL's host is allowed.
    /// Supports exact matches (example.org) and wildcard subdomains (*.example.org).
    public func isAllowed(_ url: String) -> Bool {
        guard let parsed = URL(string: url),
              let host = parsed.host?.lowercased() else {
            return false
        }
        
        return allowlistLock.withLock {
            // Check each allowed pattern
            for allowed in allowedHosts {
                let allowedLower = allowed.lowercased()
                
                // Exact match
                if host == allowedLower {
                    return true
                }
                
                // Wildcard subdomain: *.example.org matches www.example.org, api.example.org, etc.
                if allowedLower.hasPrefix("*.") {
                    let domain = String(allowedLower.dropFirst(2)) // Remove "*."
                    if host == domain || host.hasSuffix(".\(domain)") {
                        return true
                    }
                }
            }
            return false
        }
    }
    
    public func setAllowedHosts(_ hosts: [String]) {
        allowlistLock.withLock {
            self.allowedHosts = Set(hosts.map { $0.lowercased() })
        }
    }
    
    // MARK: - HTTP Request
    
    public func request(_ request: HttpRequest) async throws -> HttpResponse {
        // Validate URL
        guard let url = URL(string: request.url) else {
            throw BridgeError.invalidURL(request.url)
        }
        
        // Check protocol
        guard url.scheme == "http" || url.scheme == "https" else {
            throw BridgeError.unsupportedProtocol(url.scheme ?? "unknown")
        }
        
        // Check allowlist for initial URL
        if !isAllowed(request.url) {
            throw BridgeError.notAllowed(request.url)
        }
        
        var currentRequest = URLRequest(url: url)
        currentRequest.httpMethod = request.method.uppercased()
        currentRequest.cachePolicy = .reloadIgnoringLocalCacheData
        
        if let headers = request.headers {
            for (key, value) in headers {
                currentRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        if let body = request.body, !body.isEmpty {
            currentRequest.httpBody = body.data(using: .utf8)
        }
        
        var currentURL = url
        var currentMethod = request.method.uppercased()
        var currentBody = request.body
        
        for _ in 0...maxRedirects {
            // Re-validate allowlist for each redirect
            if !isAllowed(currentURL.absoluteString) {
                throw BridgeError.notAllowed(currentURL.absoluteString)
            }
            
            currentRequest.url = currentURL
            currentRequest.httpMethod = currentMethod
            if let body = currentBody {
                currentRequest.httpBody = body.data(using: .utf8)
            } else {
                currentRequest.httpBody = nil
            }
            
            logger.log("HTTP \(currentMethod) \(currentURL)", level: 0, context: nil)
            
            let (data, response) = try await session.data(for: currentRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BridgeError.networkError("Invalid response type")
            }
            
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            
            let finalResponse = HttpResponse(
                status: httpResponse.statusCode,
                url: currentURL.absoluteString,
                headers: headers,
                body: responseBody
            )
            
            // Handle redirects
            if httpResponse.statusCode >= 300 && httpResponse.statusCode < 400,
               let location = httpResponse.allHeaderFields["Location"] as? String,
               let redirectURL = URL(string: location, relativeTo: currentURL) {
                
                currentURL = redirectURL
                if httpResponse.statusCode == 303 || 
                   (httpResponse.statusCode == 301 || httpResponse.statusCode == 302) && currentMethod == "POST" {
                    currentMethod = "GET"
                    currentBody = nil
                }
                continue
            }
            
            return finalResponse
        }
        
        throw BridgeError.networkError("Too many redirects")
    }
    
    // MARK: - HTML Parsing
    
    public func parseHTML(_ html: String) async throws -> ParsedDocument {
        let document = try SwiftSoup.parse(html)
        let documentId = UUID().uuidString
        
        documentQueue.async(flags: .barrier) {
            self.documents[documentId] = document
        }
        
        let title = try? document.title()
        return ParsedDocument(documentId: documentId, title: title, url: "")
    }
    
    // MARK: - Document Selectors
    
    public func querySelector(documentId: String, selector: String) async throws -> ElementResult? {
        let document = documentQueue.sync { documents[documentId] }
        guard let document else {
            throw BridgeError.documentNotFound(documentId)
        }
        
        guard let element = try document.select(selector).first() else {
            return nil
        }
        
        return try makeElementResult(from: element)
    }
    
    public func querySelectorAll(documentId: String, selector: String) async throws -> [ElementResult] {
        let document = documentQueue.sync { documents[documentId] }
        guard let document else {
            throw BridgeError.documentNotFound(documentId)
        }
        
        let elements = try document.select(selector)
        var results: [ElementResult] = []
        
        for element in elements {
            if let result = try? makeElementResult(from: element) {
                results.append(result)
            }
        }
        
        return results
    }
    
    private func makeElementResult(from element: Element) throws -> ElementResult {
        let elementId = UUID().uuidString
        let tagName = element.tagName()
        let textContent = try element.text()
        let outerHTML = try element.outerHtml()
        
        // Parse attributes from outerHTML since SwiftSoup's Attributes is internal
        let attributes = parseAttributes(from: outerHTML)
        
        let result = ElementResult(
            elementId: elementId,
            tagName: tagName,
            textContent: textContent.isEmpty ? nil : textContent,
            attributes: attributes,
            outerHTML: outerHTML
        )
        
        elementQueue.async(flags: .barrier) {
            self.elements[elementId] = element
        }
        
        return result
    }
    
    /// Parse attributes from outerHTML string using regex
    private func parseAttributes(from html: String) -> [String: String] {
        var attributes: [String: String] = [:]
        // Regex to match attribute="value" or attribute='value'
        let pattern = #"(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: html.utf16.count)
        regex?.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let keyRange = Range(match.range(at: 1), in: html),
                  let valueRange = match.range(at: 2).location != NSNotFound 
                    ? Range(match.range(at: 2), in: html)
                    : Range(match.range(at: 3), in: html) else {
                return
            }
            let key = String(html[keyRange])
            let value = String(html[valueRange])
            attributes[key] = value
        }
        return attributes
    }
    
    public func getAttribute(elementId: String, name: String) async throws -> String? {
        let element = elementQueue.sync { elements[elementId] }
        guard let element else {
            throw BridgeError.elementNotFound(elementId)
        }
        return try element.attr(name)
    }
    
    public func getTextContent(elementId: String) async throws -> String? {
        let element = elementQueue.sync { elements[elementId] }
        guard let element else {
            throw BridgeError.elementNotFound(elementId)
        }
        return try element.text()
    }
    
    public func releaseElement(_ elementId: String) {
        elementQueue.async(flags: .barrier) {
            self.elements.removeValue(forKey: elementId)
        }
    }
    
    public func releaseDocument(_ documentId: String) {
        documentQueue.async(flags: .barrier) {
            self.documents.removeValue(forKey: documentId)
        }
    }
    
    // MARK: - Logging
    
    public func log(_ message: String, _ level: Int, _ context: [String: Any]?) {
        logger.log(message, level: level, context: context)
    }
    
    public func error(_ message: String, _ level: Int, _ context: [String: Any]?) {
        logger.error(message, level: level, context: context)
    }
    
    public func warn(_ message: String, _ level: Int, _ context: [String: Any]?) {
        logger.warn(message, level: level, context: context)
    }
    
    // MARK: - Timers
    
    public func setTimeout(_ callback: @escaping @Sendable () -> Void, _ ms: Int) -> Int {
        let id = timerQueue.sync {
            timerCounter += 1
            return timerCounter
        }
        
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(ms) / 1000.0, repeats: false) { [weak self] _ in
            callback()
            self?.timerQueue.async(flags: .barrier) {
                self?.timers.removeValue(forKey: id)
            }
        }
        
        let handle = TimerHandle(id: id, timer: timer)
        timerQueue.async(flags: .barrier) {
            self.timers[id] = handle
        }
        
        return id
    }
    
    public func clearTimeout(_ id: Int) {
        timerQueue.async(flags: .barrier) {
            if let handle = self.timers.removeValue(forKey: id) {
                handle.invalidate()
            }
        }
    }
    
    public func disposeTimers() {
        timerQueue.async(flags: .barrier) {
            for (_, handle) in self.timers {
                handle.invalidate()
            }
            self.timers.removeAll()
        }
    }
    
    // MARK: - Scripts
    
    public func getScripts(documentId: String) async throws -> [String] {
        let document = documentQueue.sync { documents[documentId] }
        guard let document else {
            throw BridgeError.documentNotFound(documentId)
        }
        
        let scripts = try document.select("script")
        return scripts.map { $0.data() }.filter { !$0.isEmpty }
    }
    
    // Allow external read access to documents for detection scoring
    func getDocument(_ documentId: String) -> Document? {
        documentQueue.sync { documents[documentId] }
    }
}

// MARK: - Logger

public struct Logger: Sendable {
    public init() {}
    
    public func log(_ message: String, level: Int, context: [String: Any]?) {
        let prefix = level >= 2 ? "⚠️" : level >= 1 ? "ℹ️" : "📝"
        var output = "\(prefix) [NativeBridge] \(message)"
        if let context = context, !context.isEmpty {
            output += " \(context)"
        }
        print(output)
    }
    
    public func error(_ message: String, level: Int, context: [String: Any]?) {
        var output = "❌ [NativeBridge] \(message)"
        if let context = context, !context.isEmpty {
            output += " \(context)"
        }
        print(output)
    }
    
    public func warn(_ message: String, level: Int, context: [String: Any]?) {
        var output = "⚠️ [NativeBridge] \(message)"
        if let context = context, !context.isEmpty {
            output += " \(context)"
        }
        print(output)
    }
}

// MARK: - Document Storage Extension

extension NativeBridgeImpl {
    /// Store a pre-parsed document (for testing)
    func storeDocument(_ document: Document, id: String? = nil) -> String {
        let documentId = id ?? UUID().uuidString
        documentQueue.async(flags: .barrier) {
            self.documents[documentId] = document
        }
        return documentId
    }
    
    /// Get document count (for debugging)
    var documentCount: Int {
        documentQueue.sync { documents.count }
    }
    
    var elementCount: Int {
        elementQueue.sync { elements.count }
    }
}