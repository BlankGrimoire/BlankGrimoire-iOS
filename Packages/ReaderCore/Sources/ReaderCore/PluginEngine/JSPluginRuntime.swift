// SPDX-License-Identifier: MPL-2.0

import Foundation
@preconcurrency import JavaScriptCore

private struct LoadedAdapter {
    let value: JavaScriptCore.JSValue
    let id: String
    let version: String
    let apiVersion: Int
}

/// Resumes a checked continuation at most once.
private final class PromiseContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: String) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<String, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

/// Loads the SDK JavaScript runtime and executes one adapter in isolation.
///
/// Every adapter owns a separate `JSVirtualMachine` and `JSContext`. Calls are
/// serialized by the actor, results cross the boundary only as JSON strings,
/// and typed helpers decode those strings into contract DTOs.
public actor JSPluginRuntime {
    public static let supportedAPIVersion = ContractVersion.current

    /// Identifier declared by the loaded adapter bundle.
    public nonisolated let adapterID: String
    /// Version declared by the loaded adapter bundle.
    public nonisolated let adapterVersion: String
    /// API version declared by the loaded adapter bundle.
    public nonisolated let adapterAPIVersion: Int

    private let virtualMachine: JSVirtualMachine
    private let context: JSContext
    private let runtime: JavaScriptCore.JSValue
    private let adapter: JavaScriptCore.JSValue
    private let documentStore: PluginDocumentStore
    private let bridge: PluginBridge
    private let logger: PluginLogger

    private var requestBridgeInstalled = false
    private var disposed = false

    public init(
        runtimeScript: String,
        adapterScript: String,
        manifest: AdapterManifest? = nil,
        bridge: PluginBridge,
        logger: PluginLogger = ConsolePluginLogger()
    ) throws {
        guard let virtualMachine = JSVirtualMachine(),
            let context = JSContext(virtualMachine: virtualMachine)
        else {
            throw PluginEngineError.contextCreationFailed
        }

        let documentStore = PluginDocumentStore()
        self.virtualMachine = virtualMachine
        self.context = context
        self.documentStore = documentStore
        self.bridge = bridge
        self.logger = logger

        try Self.configure(context: context, documentStore: documentStore, logger: logger, bridge: bridge)

        let loadedAdapter = try Self.loadAdapter(adapterScript, in: context, manifest: manifest)
        let runtime = try Self.loadRuntime(runtimeScript, in: context)

        self.adapter = loadedAdapter.value
        self.adapterID = loadedAdapter.id
        self.adapterVersion = loadedAdapter.version
        self.adapterAPIVersion = loadedAdapter.apiVersion
        self.runtime = runtime
    }

    /// Loads an adapter bundle from disk using the vendored runtime by default.
    public static func load(
        adapterScriptURL: URL,
        manifest: AdapterManifest? = nil,
        runtimeScriptURL: URL? = nil,
        bridge: PluginBridge,
        logger: PluginLogger = ConsolePluginLogger()
    ) throws -> JSPluginRuntime {
        let runtimeURL: URL
        if let runtimeScriptURL {
            runtimeURL = runtimeScriptURL
        } else {
            runtimeURL = try PluginRuntimeResources.runtimeScriptURL()
        }

        let runtimeScript: String
        do {
            runtimeScript = try String(contentsOf: runtimeURL, encoding: .utf8)
        } catch {
            throw PluginEngineError.runtimeLoadFailed(error.localizedDescription)
        }

        let adapterScript: String
        do {
            adapterScript = try String(contentsOf: adapterScriptURL, encoding: .utf8)
        } catch {
            throw PluginEngineError.adapterLoadFailed(error.localizedDescription)
        }

        return try JSPluginRuntime(
            runtimeScript: runtimeScript,
            adapterScript: adapterScript,
            manifest: manifest,
            bridge: bridge,
            logger: logger
        )
    }

    // MARK: - Invocation

    /// Calls the SDK JSON dispatcher and returns its raw JSON result.
    public func invoke(
        method: String,
        argumentsJSON: String = "{}",
        in page: PluginPageContext
    ) async throws -> String {
        guard !disposed else {
            throw PluginEngineError.disposed
        }

        installRequestBridgeIfNeeded()

        let documentID = try documentStore.parse(page.html)
        defer { documentStore.release(documentID) }

        let document = try makeDocument(documentID)
        let siteContext = try makeJSValue(
            SiteContext(baseURL: page.baseURL, siteName: page.siteName, overrides: page.overrides)
        )

        guard let options = JavaScriptCore.JSValue(newObjectIn: context) else {
            throw PluginEngineError.dispatchFailed("Could not create the runtime options object")
        }
        options.setObject(adapter, forKeyedSubscript: "adapter" as NSString)
        options.setObject(siteContext, forKeyedSubscript: "context" as NSString)
        options.setObject(document, forKeyedSubscript: "document" as NSString)

        if let native = context.objectForKeyedSubscript("__native"),
            let parseHTML = native.objectForKeyedSubscript("parseHTML"),
            !parseHTML.isUndefined
        {
            options.setObject(parseHTML, forKeyedSubscript: "parseHTML" as NSString)
        }

        guard let dispatch = runtime.objectForKeyedSubscript("dispatch"), !dispatch.isUndefined else {
            throw PluginEngineError.dispatchFailed("The runtime does not expose dispatch")
        }

        context.exception = nil
        let promise = dispatch.call(withArguments: [options, method, argumentsJSON])
        if let exception = context.exception {
            context.exception = nil
            throw PluginEngineError.dispatchFailed(exception.toString())
        }

        guard let promise, promise.isObject else {
            throw PluginEngineError.dispatchFailed("dispatch did not return a promise")
        }

        return try await string(from: promise)
    }

    public func search(_ query: SearchQuery, in page: PluginPageContext) async throws -> PagedResult<MangaSummary> {
        let json = try await invoke(method: "search", argumentsJSON: encode(query), in: page)
        return try decode(PagedResult<MangaSummary>.self, from: json)
    }

    public func details(for key: String, in page: PluginPageContext) async throws -> MangaDetails {
        let json = try await invoke(method: "details", argumentsJSON: encode(["key": key]), in: page)
        return try decode(MangaDetails.self, from: json)
    }

    public func chapters(for key: String, in page: PluginPageContext) async throws -> [Chapter] {
        let json = try await invoke(method: "chapters", argumentsJSON: encode(["key": key]), in: page)
        return try decode([Chapter].self, from: json)
    }

    public func pages(
        mangaKey: String,
        chapterKey: String,
        in page: PluginPageContext
    ) async throws -> [Page] {
        let arguments = ["mangaKey": mangaKey, "chapterKey": chapterKey]
        let json = try await invoke(method: "pages", argumentsJSON: encode(arguments), in: page)
        return try decode([Page].self, from: json)
    }

    /// Releases documents and bridge globals. Later calls throw `.disposed`.
    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        documentStore.clear()
        bridge.dispose()
        context.setObject(nil, forKeyedSubscript: "__native" as NSString)
        context.setObject(nil, forKeyedSubscript: "__makeDocument" as NSString)
        context.setObject(nil, forKeyedSubscript: "__resolveRequest" as NSString)
    }

    // MARK: - Context setup

    private static func configure(
        context: JSContext,
        documentStore: PluginDocumentStore,
        logger: PluginLogger,
        bridge: PluginBridge
    ) throws {
        context.exceptionHandler = { _, exception in
            logger.error(
                "JavaScript exception: \(exception?.toString() ?? "unknown")",
                level: 2,
                context: nil
            )
        }

        installDOMBridge(in: context, documentStore: documentStore)
        installLoggingBridge(in: context, logger: logger)
        installTimerBridge(in: context, bridge: bridge)

        let parseHTML: @convention(block) (String) -> String? = { html in
            try? documentStore.parse(html)
        }
        context.setObject(parseHTML, forKeyedSubscript: "__nativeParseHTML" as NSString)

        context.exception = nil
        _ = context.evaluateScript(
            bootstrapScript,
            withSourceURL: URL(fileURLWithPath: "plugin-bootstrap.js")
        )
        if let exception = context.exception {
            throw PluginEngineError.runtimeLoadFailed(exception.toString())
        }
    }

    private static func installDOMBridge(
        in context: JSContext,
        documentStore: PluginDocumentStore
    ) {
        let querySelector: @convention(block) (String, String) -> String? = { nodeID, selector in
            documentStore.querySelector(nodeID, selector)
        }
        let querySelectorAll: @convention(block) (String, String) -> [String] = { nodeID, selector in
            documentStore.querySelectorAll(nodeID, selector)
        }
        let documentElement: @convention(block) (String) -> String? = { documentID in
            documentStore.documentElement(documentID)
        }
        let getAttribute: @convention(block) (String, String) -> String? = { nodeID, name in
            documentStore.getAttribute(nodeID, name)
        }
        let textContent: @convention(block) (String) -> String? = { nodeID in
            documentStore.textContent(nodeID)
        }
        let innerHTML: @convention(block) (String) -> String? = { nodeID in
            documentStore.innerHTML(nodeID)
        }

        context.setObject(querySelector, forKeyedSubscript: "__domQuerySelector" as NSString)
        context.setObject(querySelectorAll, forKeyedSubscript: "__domQuerySelectorAll" as NSString)
        context.setObject(documentElement, forKeyedSubscript: "__domDocumentElement" as NSString)
        context.setObject(getAttribute, forKeyedSubscript: "__domGetAttribute" as NSString)
        context.setObject(textContent, forKeyedSubscript: "__domTextContent" as NSString)
        context.setObject(innerHTML, forKeyedSubscript: "__domInnerHTML" as NSString)
    }

    private static func installLoggingBridge(in context: JSContext, logger: PluginLogger) {
        let log: @convention(block) (String) -> Void = { argumentsJSON in
            logger.log(Self.logMessage(from: argumentsJSON), level: 0, context: nil)
        }
        let error: @convention(block) (String) -> Void = { argumentsJSON in
            logger.error(Self.logMessage(from: argumentsJSON), level: 2, context: nil)
        }
        let warn: @convention(block) (String) -> Void = { argumentsJSON in
            logger.warn(Self.logMessage(from: argumentsJSON), level: 1, context: nil)
        }

        context.setObject(log, forKeyedSubscript: "__nativeLog" as NSString)
        context.setObject(error, forKeyedSubscript: "__nativeError" as NSString)
        context.setObject(warn, forKeyedSubscript: "__nativeWarn" as NSString)
    }

    private static func installTimerBridge(in context: JSContext, bridge: PluginBridge) {
        let setTimeout: @convention(block) (Double, @Sendable @escaping @convention(block) () -> Void) -> Int = {
            ms, callback in
            bridge.setTimeout(Int(ms), callback)
        }
        let setInterval: @convention(block) (Double, @Sendable @escaping @convention(block) () -> Void) -> Int = {
            ms, callback in
            bridge.setInterval(Int(ms), callback)
        }
        let clearTimeout: @convention(block) (Int) -> Void = { id in
            bridge.clearTimeout(id)
        }
        context.setObject(setTimeout, forKeyedSubscript: "__nativeSetTimeout" as NSString)
        context.setObject(setInterval, forKeyedSubscript: "__nativeSetInterval" as NSString)
        context.setObject(clearTimeout, forKeyedSubscript: "__nativeClearTimeout" as NSString)
    }

    private static func loadAdapter(
        _ script: String,
        in context: JSContext,
        manifest: AdapterManifest?
    ) throws -> LoadedAdapter {
        context.exception = nil
        _ = context.evaluateScript(
            script,
            withSourceURL: URL(fileURLWithPath: "adapter.js")
        )
        if let exception = context.exception {
            throw PluginEngineError.adapterLoadFailed(exception.toString())
        }

        guard let exports = context.objectForKeyedSubscript("BlankGrimoireRuntime"), exports.isObject else {
            throw PluginEngineError.adapterLoadFailed(
                "The adapter bundle does not expose a BlankGrimoireRuntime global"
            )
        }

        let adapter: JavaScriptCore.JSValue
        if let value = exports.objectForKeyedSubscript("default"), value.isObject {
            adapter = value
        } else if let value = exports.objectForKeyedSubscript("adapter"), value.isObject {
            adapter = value
        } else if let id = exports.objectForKeyedSubscript("id"), id.isString {
            adapter = exports
        } else {
            throw PluginEngineError.invalidAdapter("Missing default adapter export")
        }

        guard let idValue = adapter.objectForKeyedSubscript("id"),
            idValue.isString,
            let id = idValue.toString(),
            !id.isEmpty
        else {
            throw PluginEngineError.invalidAdapter("Missing adapter id")
        }
        guard let selectors = adapter.objectForKeyedSubscript("selectors"), selectors.isObject else {
            throw PluginEngineError.invalidAdapter("Missing adapter selectors")
        }
        guard let apiVersionValue = adapter.objectForKeyedSubscript("apiVersion"), apiVersionValue.isNumber else {
            throw PluginEngineError.invalidAdapter("Missing adapter apiVersion")
        }

        let apiVersion = Int(apiVersionValue.toInt32())
        guard apiVersion == ContractVersion.current else {
            throw PluginEngineError.apiVersionMismatch(
                expected: ContractVersion.current,
                found: apiVersion
            )
        }

        let versionValue = adapter.objectForKeyedSubscript("version")
        let version = versionValue?.isString == true ? (versionValue?.toString() ?? "") : ""

        if let manifest {
            guard manifest.id == id, manifest.version == version else {
                throw PluginEngineError.invalidManifest(
                    "expected \(manifest.id)@\(manifest.version), found \(id)@\(version)"
                )
            }
        }

        return LoadedAdapter(value: adapter, id: id, version: version, apiVersion: apiVersion)
    }

    private static func loadRuntime(_ script: String, in context: JSContext) throws -> JavaScriptCore.JSValue {
        context.exception = nil
        _ = context.evaluateScript(
            script,
            withSourceURL: URL(fileURLWithPath: "runtime.js")
        )
        if let exception = context.exception {
            throw PluginEngineError.runtimeLoadFailed(exception.toString())
        }

        guard let runtime = context.objectForKeyedSubscript("BlankGrimoireRuntime"), runtime.isObject else {
            throw PluginEngineError.runtimeLoadFailed(
                "The runtime bundle does not expose a BlankGrimoireRuntime global"
            )
        }

        guard let apiVersion = runtime.objectForKeyedSubscript("__apiVersion"), apiVersion.isNumber else {
            throw PluginEngineError.runtimeLoadFailed("The runtime does not expose __apiVersion")
        }
        let found = Int(apiVersion.toInt32())
        guard found == supportedAPIVersion else {
            throw PluginEngineError.apiVersionMismatch(
                expected: supportedAPIVersion,
                found: found
            )
        }

        guard let dispatch = runtime.objectForKeyedSubscript("dispatch"), !dispatch.isUndefined else {
            throw PluginEngineError.runtimeLoadFailed("The runtime does not expose dispatch")
        }

        return runtime
    }

    // MARK: - Promise bridge

    private func installRequestBridgeIfNeeded() {
        guard !requestBridgeInstalled else {
            return
        }
        requestBridgeInstalled = true

        let request: @convention(block) (String, String) -> Void = { [weak self] payload, requestID in
            Task { [weak self] in
                await self?.handleRequest(payload, requestID: requestID)
            }
        }
        context.setObject(request, forKeyedSubscript: "__nativeRequest" as NSString)
    }

    private func handleRequest(_ payload: String, requestID: String) async {
        guard !disposed else {
            return
        }

        do {
            let request = try JSONDecoder()
                .decode(PluginRequestPayload.self, from: Data(payload.utf8))
                .httpRequest()
            let response = try await bridge.request(request)
            let data = try JSONEncoder().encode(response)
            resolveRequest(
                requestID,
                error: nil,
                responseJSON: String(decoding: data, as: UTF8.self)
            )
        } catch {
            resolveRequest(requestID, error: error.localizedDescription, responseJSON: nil)
        }
    }

    private func resolveRequest(_ id: String, error: String?, responseJSON: String?) {
        guard !disposed,
            let resolve = context.objectForKeyedSubscript("__resolveRequest"),
            !resolve.isUndefined
        else {
            return
        }

        _ = resolve.call(withArguments: [id, error ?? NSNull(), responseJSON ?? NSNull()])
        if let exception = context.exception {
            context.exception = nil
            logger.error(
                "Failed to resolve a JavaScript request: \(exception.toString() ?? "unknown")",
                level: 2,
                context: nil
            )
        }
    }

    private func string(from promise: JavaScriptCore.JSValue) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let box = PromiseContinuation(continuation)
            let fulfilled: @convention(block) (JavaScriptCore.JSValue) -> Void = { value in
                box.resume(returning: value.toString() ?? "null")
            }
            let rejected: @convention(block) (JavaScriptCore.JSValue) -> Void = { error in
                box.resume(
                    throwing: PluginEngineError.dispatchFailed(error.toString() ?? "unknown error")
                )
            }

            context.exception = nil
            _ = promise.invokeMethod("then", withArguments: [fulfilled, rejected])
            if let exception = context.exception {
                context.exception = nil
                box.resume(
                    throwing: PluginEngineError.dispatchFailed(exception.toString() ?? "unknown error")
                )
            }
        }
    }

    // MARK: - JS helpers

    private func makeDocument(_ documentID: String) throws -> JavaScriptCore.JSValue {
        guard let factory = context.objectForKeyedSubscript("__makeDocument"),
            let document = factory.call(withArguments: [documentID]),
            document.isObject
        else {
            throw PluginEngineError.dispatchFailed("Could not create the JavaScript document")
        }
        return document
    }

    private func makeJSValue<T: Encodable>(_ value: T) throws -> JavaScriptCore.JSValue {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw PluginEngineError.encodingFailed(error.localizedDescription)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PluginEngineError.encodingFailed(error.localizedDescription)
        }

        guard let result = JavaScriptCore.JSValue(object: object, in: context) else {
            throw PluginEngineError.encodingFailed("Could not convert the value to JavaScript")
        }
        return result
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        do {
            let data = try JSONEncoder().encode(value)
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw PluginEngineError.encodingFailed(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw PluginEngineError.decodingFailed(error.localizedDescription)
        }
    }

    private static func logMessage(from argumentsJSON: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
            let arguments = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return argumentsJSON
        }
        return arguments.map { String(describing: $0) }.joined(separator: " ")
    }

    private struct PluginRequestPayload: Decodable {
        let url: String
        let method: String?
        let headers: [String: String]?
        let body: String?

        func httpRequest() -> HttpRequest {
            HttpRequest(
                url: url,
                method: method ?? "GET",
                headers: headers,
                body: body
            )
        }
    }

    private static let bootstrapScript = """
        (function () {
            "use strict";

            var pendingRequests = Object.create(null);
            var nextRequestID = 0;

            function makeNode(id, isDocument) {
                if (id === null || id === undefined || id === "") {
                    return null;
                }

                var node = {
                    get textContent() {
                        var value = __domTextContent(id);
                        return value === undefined ? null : value;
                    },
                    get innerHTML() {
                        var value = __domInnerHTML(id);
                        return value === undefined ? null : value;
                    },
                    getAttribute: function (name) {
                        var value = __domGetAttribute(id, String(name));
                        return value === undefined ? null : value;
                    },
                    querySelector: function (selector) {
                        return makeNode(__domQuerySelector(id, String(selector)), false);
                    },
                    querySelectorAll: function (selector) {
                        var ids = __domQuerySelectorAll(id, String(selector)) || [];
                        var result = [];
                        for (var index = 0; index < ids.length; index += 1) {
                            result.push(makeNode(ids[index], false));
                        }
                        return result;
                    }
                };

                if (isDocument) {
                    node.documentElement = makeNode(__domDocumentElement(id), false);
                }
                return node;
            }

            globalThis.__makeDocument = function (id) {
                return makeNode(id, true);
            };

            globalThis.__resolveRequest = function (id, error, responseJSON) {
                var pending = pendingRequests[id];
                if (!pending) {
                    return;
                }
                delete pendingRequests[id];

                if (error) {
                    pending.reject(new Error(String(error)));
                    return;
                }

                try {
                    pending.resolve(JSON.parse(responseJSON));
                } catch (parseError) {
                    pending.reject(parseError);
                }
            };

            globalThis.__native = {
                request: function (request) {
                    return new Promise(function (resolve, reject) {
                        var id = String(++nextRequestID);
                        pendingRequests[id] = { resolve: resolve, reject: reject };
                        __nativeRequest(JSON.stringify(request), id);
                    });
                },
                setTimeout: function (callback, ms) {
                    return __nativeSetTimeout(ms, callback);
                },
                clearTimeout: function (id) {
                    __nativeClearTimeout(id);
                },
                setInterval: function (callback, ms) {
                    return __nativeSetInterval(ms, callback);
                },
                clearInterval: function (id) {
                    __nativeClearTimeout(id);
                },
                parseHTML: function (html) {
                    return makeNode(__nativeParseHTML(String(html)), true);
                },
                log: function () {
                    __nativeLog(JSON.stringify(Array.prototype.slice.call(arguments)));
                },
                error: function () {
                    __nativeError(JSON.stringify(Array.prototype.slice.call(arguments)));
                },
                warn: function () {
                    __nativeWarn(JSON.stringify(Array.prototype.slice.call(arguments)));
                }
            };
        })();
        """
}

/// Locates the runtime bundle vendored into the ReaderCore target.
public enum PluginRuntimeResources {
    public static func runtimeScriptURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "runtime", withExtension: "js") else {
            throw PluginEngineError.runtimeResourceMissing
        }
        return url
    }

    public static func runtimeScript() throws -> String {
        try String(contentsOf: runtimeScriptURL(), encoding: .utf8)
    }
}
