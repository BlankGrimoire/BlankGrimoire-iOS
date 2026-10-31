// SPDX-License-Identifier: MPL-2.0

import Combine
import Foundation
@preconcurrency import JavaScriptCore

// MARK: - Plugin Engine Errors

public enum PluginEngineError: Error, LocalizedError, Sendable {
    case contextCreationFailed
    case bundleLoadFailed(String)
    case adapterNotFound(String)
    case invalidBundle(String)
    case dispatchFailed(String)
    case apiVersionMismatch(expected: Int, found: Int)
    case bridgeNotInitialized

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed: return "Failed to create JSContext"
        case .bundleLoadFailed(let msg): return "Failed to load bundle: \(msg)"
        case .adapterNotFound(let id): return "Adapter not found: \(id)"
        case .invalidBundle(let msg): return "Invalid bundle: \(msg)"
        case .dispatchFailed(let msg): return "Dispatch failed: \(msg)"
        case .apiVersionMismatch(let expected, let found):
            return "API version mismatch: expected \(expected), found \(found)"
        case .bridgeNotInitialized: return "Native bridge not initialized"
        }
    }
}

// MARK: - Adapter Bundle Info

public struct AdapterBundleInfo: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let detectionSignature: ThemeSignature
    public let sha256: String
    public let bundlePath: String

    public init(
        id: String, name: String, version: String, apiVersion: Int, detectionSignature: ThemeSignature, sha256: String,
        bundlePath: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.detectionSignature = detectionSignature
        self.sha256 = sha256
        self.bundlePath = bundlePath
    }
}

// MARK: - Adapter Runtime State

/// Runtime state for a loaded adapter
public final class AdapterRuntime {
    public let info: AdapterBundleInfo
    public let context: JSContext
    public let bridge: NativeBridgeImpl
    public let virtualMachine: JSVirtualMachine

    private var isDisposed = false

    public init(info: AdapterBundleInfo, context: JSContext, bridge: NativeBridgeImpl, virtualMachine: JSVirtualMachine)
    {
        self.info = info
        self.context = context
        self.bridge = bridge
        self.virtualMachine = virtualMachine
    }

    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true

        // Clear bridge references
        context.setObject(nil, forKeyedSubscript: "__native" as NSString)
        context.setObject(nil, forKeyedSubscript: "console" as NSString)

        // Invalidate timers
        bridge.disposeTimers()
    }

    deinit {
        if !isDisposed {
            // Can't call dispose() from deinit due to actor isolation
            // Timers will be cleaned up when bridge is deallocated
        }
    }
}

// MARK: - Plugin Engine

/// Manages JavaScriptCore contexts and adapter lifecycle
public final class PluginEngine: ObservableObject {
    public static let supportedAPIVersion = ContractVersion.current

    @Published public private(set) var loadedAdapters: [String: AdapterRuntime] = [:]
    @Published public private(set) var currentAdapter: AdapterRuntime?

    private let bridge: NativeBridgeImpl
    private let virtualMachine: JSVirtualMachine

    public init(allowedHosts: [String] = []) {
        self.bridge = NativeBridgeImpl(allowedHosts: allowedHosts)
        self.virtualMachine = JSVirtualMachine()
    }

    /// Load an adapter bundle
    public func loadAdapter(from bundlePath: String, manifest: AdapterManifest) async throws -> AdapterRuntime {
        // Read bundle
        let bundleURL = URL(fileURLWithPath: bundlePath)
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw PluginEngineError.bundleLoadFailed("Bundle not found at \(bundlePath)")
        }

        let bundleSource = try String(contentsOf: bundleURL, encoding: .utf8)

        // Create isolated context
        let context = JSContext(virtualMachine: virtualMachine)
        guard let context = context else {
            throw PluginEngineError.contextCreationFailed
        }

        // Set up custom executor for this context
        context.exceptionHandler = { context, exception in
            print("❌ [JSContext] Exception: \(exception?.toString() ?? "unknown")")
        }

        // Configure context
        configureContext(context)

        // Inject native bridge
        injectBridge(into: context)

        // Load bundle
        _ = context.evaluateScript(bundleSource, withSourceURL: bundleURL)
        if let exception = context.exception {
            throw PluginEngineError.bundleLoadFailed(exception.toString())
        }

        // Verify API version
        let apiVersion = context.objectForKeyedSubscript("__apiVersion")?.toInt32() ?? 0
        if apiVersion != Self.supportedAPIVersion {
            throw PluginEngineError.apiVersionMismatch(expected: Self.supportedAPIVersion, found: Int(apiVersion))
        }

        // Verify dispatch function exists
        guard context.objectForKeyedSubscript("dispatch") != nil else {
            throw PluginEngineError.invalidBundle("Bundle missing dispatch function")
        }

        // Create runtime
        let bundleInfo = AdapterBundleInfo(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            apiVersion: manifest.apiVersion,
            detectionSignature: manifest.detectionSignature,
            sha256: manifest.sha256,
            bundlePath: bundlePath
        )

        let runtime = AdapterRuntime(
            info: bundleInfo,
            context: context,
            bridge: bridge,
            virtualMachine: virtualMachine
        )

        loadedAdapters[manifest.id] = runtime

        return runtime
    }

    /// Set current active adapter
    public func setCurrentAdapter(_ id: String) throws {
        guard let runtime = loadedAdapters[id] else {
            throw PluginEngineError.adapterNotFound(id)
        }
        currentAdapter = runtime
    }

    /// Get current adapter runtime
    public func getCurrentRuntime() throws -> AdapterRuntime {
        guard let runtime = currentAdapter else {
            throw PluginEngineError.bridgeNotInitialized
        }
        return runtime
    }

    /// Dispatch a method call to the adapter
    public func dispatch(method: String, args: [String: Any] = [:]) async throws -> String {
        let runtime = try getCurrentRuntime()

        let argsData = try JSONSerialization.data(withJSONObject: args)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"

        // Call dispatch function
        let dispatchFn = runtime.context.objectForKeyedSubscript("dispatch")
        guard let dispatchFn = dispatchFn, !dispatchFn.isUndefined else {
            throw PluginEngineError.dispatchFailed("dispatch function not found")
        }

        let methodJS = method as NSString
        let argsJSONJS = argsJSON as NSString

        let result = dispatchFn.call(withArguments: [methodJS, argsJSONJS])

        if let exception = runtime.context.exception {
            throw PluginEngineError.dispatchFailed(exception.toString())
        }

        return result?.toString() ?? "null"
    }

    /// Detect theme for given HTML
    public func detectTheme(html: String, url: String) async throws -> DetectionResult {
        let runtime = try getCurrentRuntime()

        // Parse HTML
        let parsed = try await bridge.parseHTML(html)

        // Store document
        let documentId = parsed.documentId

        // Get detection signature from adapter
        let detectionSignature = runtime.info.detectionSignature

        // Score the signature
        let score = try await scoreSignature(detectionSignature, documentId: documentId, url: url)
        let detected = score >= detectionSignature.minScore

        return DetectionResult(
            detected: detected,
            score: score,
            detectionSignature: detectionSignature,
            documentId: documentId
        )
    }

    /// Score a detection signature against a document
    private func scoreSignature(_ signature: ThemeSignature, documentId: String, url: String) async throws -> Int {
        var total = 0

        // Check metaGenerator
        if let metaGenerator = signature.metaGenerator,
            let document = bridge.getDocument(documentId)
        {
            let metaElements = try document.select("meta[name=generator]")
            for element in metaElements {
                let content = try element.attr("content")
                if let regex = try? NSRegularExpression(pattern: metaGenerator),
                    regex.firstMatch(in: content, range: NSRange(location: 0, length: content.utf16.count)) != nil
                {
                    total += 3
                    break
                }
            }
        }

        // Check selectors
        if let selectors = signature.selectors {
            for selector in selectors {
                if let document = bridge.getDocument(documentId),
                    try document.select(selector).count > 0
                {
                    total += 2
                }
            }
        }

        // Check scriptSrc
        if let scriptSrcPatterns = signature.scriptSrc {
            for pattern in scriptSrcPatterns {
                if let document = bridge.getDocument(documentId) {
                    let scripts = try document.select("script")
                    for script in scripts {
                        let src = try script.attr("src")
                        if let regex = try? NSRegularExpression(pattern: pattern),
                            regex.firstMatch(in: src, range: NSRange(location: 0, length: src.utf16.count)) != nil
                        {
                            total += 1
                            break
                        }
                    }
                }
            }
        }

        // Check probePaths
        if let probePaths = signature.probePaths {
            for probePath in probePaths {
                do {
                    let probeURL = URL(string: probePath, relativeTo: URL(string: url))?.absoluteString ?? probePath
                    let response = try await bridge.request(HttpRequest(url: probeURL))
                    if response.status >= 200 && response.status < 300 {
                        total += 3
                    }
                } catch {
                    // Failed probe = no score
                }
            }
        }

        return total
    }

    /// Unload adapter
    public func unloadAdapter(_ id: String) {
        if let runtime = loadedAdapters.removeValue(forKey: id) {
            runtime.dispose()
        }
        if currentAdapter?.info.id == id {
            currentAdapter = nil
        }
    }

    /// Unload all adapters
    public func unloadAll() {
        for (_, runtime) in loadedAdapters {
            runtime.dispose()
        }
        loadedAdapters.removeAll()
        currentAdapter = nil
    }

    // MARK: - Private

    private func configureContext(_ context: JSContext) {
        // Enable modern JS features
        context.evaluateScript(
            """
                // Polyfills for JavaScriptCore
                if (typeof globalThis === 'undefined') { globalThis = this; }
                if (typeof Promise === 'undefined') { throw new Error('Promise not available'); }
                if (typeof Map === 'undefined') { throw new Error('Map not available'); }
                if (typeof Set === 'undefined') { throw new Error('Set not available'); }
            """)
    }

    private func injectBridge(into context: JSContext) {
        // Expose __native
        let nativeObject: [String: Any] = [
            "request": { (request: [String: Any]) -> [String: Any] in
                return [:]
            },
            "parseHTML": { (html: String) -> [String: Any] in
                return [:]
            },
            "log": { (message: String, level: Int, context: [String: Any]?) in
                self.bridge.log(message, level, context)
            },
            "error": { (message: String, level: Int, context: [String: Any]?) in
                self.bridge.error(message, level, context)
            },
            "warn": { (message: String, level: Int, context: [String: Any]?) in
                self.bridge.warn(message, level, context)
            },
            "setTimeout": { (callback: @escaping @Sendable @convention(block) () -> Void, ms: Int) -> Int in
                return self.bridge.setTimeout(callback, ms)
            },
            "clearTimeout": { (id: Int) in
                self.bridge.clearTimeout(id)
            },
        ]

        context.setObject(nativeObject, forKeyedSubscript: "__native" as NSString)

        // Expose console
        let consoleObject: [String: Any] = [
            "log": { (args: [Any]) in
                print("[JS Console] \(args.map { String(describing: $0) }.joined(separator: " "))")
            },
            "error": { (args: [Any]) in
                print("[JS Console Error] \(args.map { String(describing: $0) }.joined(separator: " "))")
            },
            "warn": { (args: [Any]) in
                print("[JS Console Warn] \(args.map { String(describing: $0) }.joined(separator: " "))")
            },
        ]
        context.setObject(consoleObject, forKeyedSubscript: "console" as NSString)

        // Expose URL polyfill
        context.evaluateScript(
            """
                if (typeof URL === 'undefined') {
                    function URL(url, base) {
                        var a = document.createElement('a');
                        a.href = base ? base + url : url;
                        return {
                            href: a.href,
                            protocol: a.protocol,
                            host: a.host,
                            hostname: a.hostname,
                            port: a.port,
                            pathname: a.pathname,
                            search: a.search,
                            hash: a.hash,
                            toString: function() { return this.href; }
                        };
                    }
                    URL.prototype.toString = function() { return this.href; }
                }
            """)
    }
}

// MARK: - Detection Result

public struct DetectionResult: Sendable {
    public let detected: Bool
    public let score: Int
    public let detectionSignature: ThemeSignature
    public let documentId: String

    public init(detected: Bool, score: Int, detectionSignature: ThemeSignature, documentId: String) {
        self.detected = detected
        self.score = score
        self.detectionSignature = detectionSignature
        self.documentId = documentId
    }
}
