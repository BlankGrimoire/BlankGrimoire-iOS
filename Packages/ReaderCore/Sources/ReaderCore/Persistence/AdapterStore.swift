// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation
import JavaScriptCore
import SwiftData

/// Adapter fields that live in the JavaScript bundle itself.
///
/// Repository-owned fields (`sha256`) are attached after decoding.
private struct AdapterBundleInspection: Decodable {
    let id: String
    let name: String?
    let version: String
    let apiVersion: Int
    let detectionSignature: ThemeSignature
    let selectors: ThemeSelectors
    let referrerHeaders: [String: String]?
}

// MARK: - Adapter Store Errors

/// Errors that can occur during adapter store operations.
public enum AdapterStoreError: Error, LocalizedError, Sendable, Equatable {
    case invalidRepositoryURL
    case networkError(String)
    case invalidIndexFormat(String)
    case publicKeyMismatch
    case signatureVerificationFailed
    case sha256Mismatch(expected: String, found: String)
    case adapterNotFound(String)
    case adapterAlreadyInstalled(String)
    case downgradeNotAllowed(id: String, installed: String, requested: String)
    case repositoryNotTrusted(String)
    case trustOnFirstUseRequired(String)
    case bundleDownloadFailed(String)
    case bundleVerificationFailed(String)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            return "Enter a full HTTPS repository index URL, for example https://example.org/index.json"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidIndexFormat(let msg):
            return "The repository did not return a valid index.json: \(msg)"
        case .publicKeyMismatch:
            return "Repository public key does not match trusted key"
        case .signatureVerificationFailed:
            return "Bundle signature verification failed"
        case .sha256Mismatch(let expected, let found):
            return "SHA-256 mismatch: expected \(expected), found \(found)"
        case .adapterNotFound(let id):
            return "Adapter not found: \(id)"
        case .adapterAlreadyInstalled(let id):
            return "Adapter already installed: \(id)"
        case .downgradeNotAllowed(let id, let installed, let requested):
            return "Cannot downgrade \(id) from \(installed) to \(requested)"
        case .repositoryNotTrusted(let url):
            return "Repository not trusted: \(url)"
        case .trustOnFirstUseRequired(let url):
            return "Trust-on-first-use required for repository: \(url)"
        case .bundleDownloadFailed(let msg):
            return "Bundle download failed: \(msg)"
        case .bundleVerificationFailed(let msg):
            return "Bundle verification failed: \(msg)"
        case .storageError(let msg):
            return "Storage error: \(msg)"
        }
    }
}

// The canonical RepositoryIndex and ExtensionEntry are defined in Domain/ContractModels.swift
// import them via the module - no redefinition needed

// The canonical AdapterManifest is defined in Domain/ContractModels.swift
// import it via the module - no redefinition needed

// MARK: - Ed25519 Verification

/// Verifies Ed25519 signatures using CryptoKit.
public enum Ed25519Verifier {
    /// Extracts the raw 32-byte public key from a "ed25519:BASE64" string.
    public static func extractPublicKey(from publicKeyString: String) throws -> Curve25519.Signing.PublicKey {
        guard publicKeyString.hasPrefix("ed25519:") else {
            throw AdapterStoreError.invalidIndexFormat("Public key must have 'ed25519:' prefix")
        }

        let base64Key = String(publicKeyString.dropFirst("ed25519:".count))
        guard let keyData = Data(base64Encoded: base64Key) else {
            throw AdapterStoreError.invalidIndexFormat("Public key is not valid base64")
        }

        guard keyData.count == 32 else {
            throw AdapterStoreError.invalidIndexFormat("Ed25519 public key must be 32 bytes")
        }

        return try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    }

    /// Returns whether two `ed25519:BASE64` strings encode the same raw key.
    public static func publicKeysMatch(_ lhs: String, _ rhs: String) -> Bool {
        guard
            let left = try? extractPublicKey(from: lhs).rawRepresentation,
            let right = try? extractPublicKey(from: rhs).rawRepresentation
        else {
            return false
        }
        return left == right
    }

    /// Verifies a base64-encoded Ed25519 signature over the given data.
    public static func verify(
        signatureBase64: String,
        data: Data,
        publicKey: Curve25519.Signing.PublicKey
    ) throws {
        guard let signatureData = Data(base64Encoded: signatureBase64) else {
            throw AdapterStoreError.signatureVerificationFailed
        }

        guard signatureData.count == 64 else {
            throw AdapterStoreError.signatureVerificationFailed
        }

        // CryptoKit uses raw signature verification
        let isValid = publicKey.isValidSignature(signatureData, for: data)
        guard isValid else {
            throw AdapterStoreError.signatureVerificationFailed
        }
    }
}

// MARK: - SHA-256 Verification

/// Computes and verifies SHA-256 hashes.
public enum SHA256Verifier {
    /// Computes the SHA-256 hash of data and returns it as a hex string.
    public static func hash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies that data matches the expected SHA-256 hex string.
    public static func verify(_ data: Data, expectedHex: String) throws {
        let computed = hash(data)
        guard computed.lowercased() == expectedHex.lowercased() else {
            throw AdapterStoreError.sha256Mismatch(expected: expectedHex, found: computed)
        }
    }
}

// MARK: - Adapter Bundle

/// Represents a downloaded and verified adapter bundle.
public struct AdapterBundle: Codable, Sendable {
    public let manifest: AdapterManifest
    public let themeAdapter: ThemeAdapter
    public let bundleData: Data
    public let sourceRepositoryURL: String
    public let installedAt: Date

    public init(
        manifest: AdapterManifest,
        themeAdapter: ThemeAdapter,
        bundleData: Data,
        sourceRepositoryURL: String,
        installedAt: Date = Date()
    ) {
        self.manifest = manifest
        self.themeAdapter = themeAdapter
        self.bundleData = bundleData
        self.sourceRepositoryURL = sourceRepositoryURL
        self.installedAt = installedAt
    }

    public var id: String { manifest.id }
    public var version: String { manifest.version }
}

// MARK: - Repository Trust (TOFU)

/// Represents a trusted repository with its public key.
public struct TrustedRepository: Codable, Sendable, Equatable {
    public let url: String
    public let name: String
    public let publicKey: String  // "ed25519:BASE64"
    public let trustedAt: Date
    public var lastVerifiedAt: Date?

    public init(
        url: String,
        name: String,
        publicKey: String,
        trustedAt: Date = Date()
    ) {
        self.url = url
        self.name = name
        self.publicKey = publicKey
        self.trustedAt = trustedAt
        self.lastVerifiedAt = nil
    }

    public func verifyIndex(_ index: RepositoryIndex) throws {
        // Public keys are compared on their decoded bytes: base64 padding and
        // whitespace differences must not change the trust decision.
        guard Ed25519Verifier.publicKeysMatch(index.publicKey, publicKey) else {
            throw AdapterStoreError.publicKeyMismatch
        }
    }

    /// Short, human-checkable fingerprint of the repository key.
    ///
    /// Derived from the decoded key bytes so different base64 encodings of the
    /// same key produce the same fingerprint. The full base64 key stays in the
    /// trust record but is unreadable when shown to a person.
    public var keyFingerprint: String {
        AdapterKeyFingerprint.short(of: publicKey)
    }
}

/// Formats adapter repository keys for display.
public enum AdapterKeyFingerprint {
    /// Returns the first 16 hex characters of the SHA-256 of the key, in
    /// groups of four (`ABCD EF01 2345 6789`).
    public static func short(of publicKey: String) -> String {
        let rawKey = publicKey.split(separator: ":").last.map(String.init) ?? publicKey
        let digest = SHA256.hash(data: Data(rawKey.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined().prefix(16)
        return stride(from: 0, to: hex.count, by: 4)
            .map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 4)
                return String(hex[start..<end])
            }
            .joined(separator: " ")
    }
}

// MARK: - Adapter Store Protocol

/// Protocol for adapter store operations.
public protocol AdapterStore: Sendable {
    /// Fetches and verifies a repository index.
    func fetchRepositoryIndex(from url: String) async throws -> RepositoryIndex

    /// Trusts a repository (TOFU - called after user confirmation).
    ///
    /// The canonical index URL is part of the trust identity. Implementations
    /// must persist it instead of deriving an identity from the index name.
    func trustRepository(_ index: RepositoryIndex, from repositoryURL: String) async throws

    /// Checks if a repository is trusted.
    func isRepositoryTrusted(_ url: String) async throws -> Bool

    /// Lists all trusted repositories.
    func listTrustedRepositories() async throws -> [TrustedRepository]

    /// Removes trust for a repository.
    func removeTrust(for url: String) async throws

    /// Installs an adapter from a trusted repository.
    func installAdapter(id: String, version: String, from repositoryURL: String) async throws -> AdapterBundle

    /// Uninstalls an adapter.
    func uninstallAdapter(id: String) async throws

    /// Lists all installed adapters.
    func listInstalledAdapters() async throws -> [AdapterBundle]

    /// Gets an installed adapter bundle by ID.
    func getInstalledAdapter(id: String) async throws -> AdapterBundle?

    /// Checks for updates for installed adapters.
    func checkForUpdates() async throws -> [(adapter: AdapterBundle, update: ExtensionEntry)]

    /// Updates an installed adapter to a new version.
    func updateAdapter(id: String, to version: String) async throws -> AdapterBundle
}

extension AdapterStore {
    /// Normalises a repository URL without performing any I/O.
    ///
    /// Kept as a protocol helper so views and tests share one definition of the
    /// canonical trust identity.
    public func canonicalRepositoryURL(_ repositoryURL: String) throws -> String {
        guard let canonical = RepositoryURL.normalizedIndexURL(from: repositoryURL) else {
            throw AdapterStoreError.invalidRepositoryURL
        }
        return canonical.absoluteString
    }
}

// MARK: - Adapter Store Implementation

/// Default implementation of `AdapterStore` using SwiftData for persistence
/// and CryptoKit for signature verification.
@MainActor
public final class DefaultAdapterStore: AdapterStore {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let logger: PluginLogger

    /// Repository requests derive a host-scoped policy from the canonical URL.
    /// The store does not accept a shared request handler because a policy for
    /// one repository must never authorise another repository or site.
    public init(
        modelContainer: ModelContainer,
        logger: PluginLogger = ConsolePluginLogger()
    ) throws {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
        self.logger = logger
    }

    /// Removes trust rows whose URL is not a canonical HTTPS index URL.
    ///
    /// Older builds inferred the trust identity from the repository display
    /// name (for example `BlankGrimoire Themes`), producing rows that can never
    /// match a real request. Valid rows are left untouched.
    @discardableResult
    public func purgeInvalidTrustedRepositories() throws -> Int {
        let descriptor = FetchDescriptor<TrustedRepositoryEntity>()
        let entities = try modelContext.fetch(descriptor)
        var removed = 0
        for entity in entities {
            let canonical = RepositoryURL.normalizedIndexURL(from: entity.url)?.absoluteString
            guard canonical == entity.url else {
                modelContext.delete(entity)
                removed += 1
                continue
            }
        }
        if removed > 0 {
            try modelContext.save()
            logger.warn(
                "Removed \(removed) invalid trusted repository entr\(removed == 1 ? "y" : "ies")",
                level: 1,
                context: nil
            )
        }
        return removed
    }

    // MARK: - Repository Index

    public func fetchRepositoryIndex(from url: String) async throws -> RepositoryIndex {
        guard let indexURL = RepositoryURL.normalizedIndexURL(from: url) else {
            throw AdapterStoreError.invalidRepositoryURL
        }

        let request = HttpRequest(url: indexURL.absoluteString, method: "GET")
        let response: HttpResponse
        do {
            response = try await repositoryRequestHandler(for: indexURL.absoluteString).perform(request)
        } catch {
            throw AdapterStoreError.networkError(Self.describedNetworkError(error))
        }

        guard response.status >= 200 && response.status < 300 else {
            throw AdapterStoreError.networkError("HTTP \(response.status): \(response.body)")
        }

        let data = Data(response.body.utf8)
        do {
            let index = try JSONDecoder().decode(RepositoryIndex.self, from: data)

            // Validate format version
            guard index.formatVersion == 1 else {
                throw AdapterStoreError.invalidIndexFormat("Unsupported format version: \(index.formatVersion)")
            }

            // Validate public key format
            guard index.publicKey.hasPrefix("ed25519:") else {
                throw AdapterStoreError.invalidIndexFormat("Public key must have 'ed25519:' prefix")
            }

            // Validate at least one extension
            guard !index.extensions.isEmpty else {
                throw AdapterStoreError.invalidIndexFormat("Repository index must contain at least one extension")
            }

            return index
        } catch let error as DecodingError {
            throw AdapterStoreError.invalidIndexFormat(error.localizedDescription)
        }
    }

    // MARK: - Trust Management (TOFU)

    public func trustRepository(_ index: RepositoryIndex, from repositoryURL: String) async throws {
        guard let indexURL = RepositoryURL.normalizedIndexURL(from: repositoryURL) else {
            throw AdapterStoreError.invalidRepositoryURL
        }

        let canonicalURL = indexURL.absoluteString
        let descriptor = FetchDescriptor<TrustedRepositoryEntity>(
            predicate: #Predicate { $0.url == canonicalURL }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            guard Ed25519Verifier.publicKeysMatch(existing.publicKey, index.publicKey) else {
                throw AdapterStoreError.publicKeyMismatch
            }
            existing.name = index.name
            existing.lastVerifiedAt = Date()
        } else {
            let trusted = TrustedRepository(
                url: canonicalURL,
                name: index.name,
                publicKey: index.publicKey
            )
            modelContext.insert(TrustedRepositoryEntity(trusted: trusted))
        }

        try modelContext.save()
        logger.log("Trusted repository: \(canonicalURL)", level: 0, context: nil)
    }

    public func isRepositoryTrusted(_ url: String) async throws -> Bool {
        guard let canonicalURL = RepositoryURL.normalizedIndexURL(from: url)?.absoluteString else {
            return false
        }
        let descriptor = FetchDescriptor<TrustedRepositoryEntity>(
            predicate: #Predicate { $0.url == canonicalURL }
        )
        let results = try modelContext.fetch(descriptor)
        return !results.isEmpty
    }

    public func listTrustedRepositories() async throws -> [TrustedRepository] {
        let descriptor = FetchDescriptor<TrustedRepositoryEntity>(
            sortBy: [SortDescriptor(\.trustedAt, order: .reverse)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toTrustedRepository() }
    }

    public func removeTrust(for url: String) async throws {
        let storedURL = RepositoryURL.normalizedIndexURL(from: url)?.absoluteString ?? url
        let descriptor = FetchDescriptor<TrustedRepositoryEntity>(
            predicate: #Predicate { $0.url == storedURL }
        )
        let entities = try modelContext.fetch(descriptor)
        for entity in entities {
            modelContext.delete(entity)
        }
        try modelContext.save()
    }

    // MARK: - Adapter Installation

    public func installAdapter(id: String, version: String, from repositoryURL: String) async throws -> AdapterBundle {
        guard let canonicalURL = RepositoryURL.normalizedIndexURL(from: repositoryURL)?.absoluteString else {
            throw AdapterStoreError.invalidRepositoryURL
        }

        // 1. Verify repository is trusted by canonical URL.
        let isTrusted = try await isRepositoryTrusted(canonicalURL)
        guard isTrusted else {
            throw AdapterStoreError.repositoryNotTrusted(canonicalURL)
        }

        // 2. Fetch repository index to get extension entry
        let index = try await fetchRepositoryIndex(from: canonicalURL)

        guard let entry = index.extensions.first(where: { $0.id == id && $0.version == version }) else {
            throw AdapterStoreError.adapterNotFound("\(id)@\(version)")
        }

        // 3. Check if already installed and reject downgrades.
        if let existing = try await getInstalledAdapter(id: id) {
            if existing.version == version {
                throw AdapterStoreError.adapterAlreadyInstalled(id)
            }
            guard AdapterVersion(version) > AdapterVersion(existing.version) else {
                throw AdapterStoreError.downgradeNotAllowed(
                    id: id,
                    installed: existing.version,
                    requested: version
                )
            }
        }

        // 4. Download bundle
        let bundleURL = resolveBundleURL(entry.bundleURL, baseURL: canonicalURL)
        let request = HttpRequest(url: bundleURL, method: "GET")
        let response: HttpResponse
        do {
            response = try await repositoryRequestHandler(for: bundleURL).perform(request)
        } catch {
            throw AdapterStoreError.bundleDownloadFailed(Self.describedNetworkError(error))
        }

        guard response.status >= 200 && response.status < 300 else {
            throw AdapterStoreError.bundleDownloadFailed("HTTP \(response.status)")
        }

        let bundleData = Data(response.body.utf8)

        // 5. Verify the bundle and parse it off the main actor. Hashing,
        // signature verification and regex parsing would otherwise block the UI.
        let trustedRepos = try await listTrustedRepositories()
        guard let trusted = trustedRepos.first(where: { $0.url == canonicalURL }) else {
            throw AdapterStoreError.repositoryNotTrusted(canonicalURL)
        }

        // The index must be signed by the same key the user approved.
        try trusted.verifyIndex(index)

        let verified = try await Self.verifyBundle(
            bundleData,
            entry: entry,
            publicKeyString: trusted.publicKey
        )

        // 6. Store bundle
        let referrerHeaders = verified.manifest.referrerHeaders ?? [:]
        let themeAdapter = ThemeAdapter(
            id: verified.manifest.id,
            name: verified.manifest.name,
            version: verified.manifest.version,
            detectionSignature: verified.manifest.detectionSignature,
            selectors: verified.selectors,
            referrerHeaders: referrerHeaders
        )
        let bundle = AdapterBundle(
            manifest: verified.manifest,
            themeAdapter: themeAdapter,
            bundleData: bundleData,
            sourceRepositoryURL: canonicalURL
        )

        let entity = InstalledAdapterEntity(bundle: bundle)
        modelContext.insert(entity)
        try modelContext.save()

        logger.log("Installed adapter: \(id)@\(version) from \(canonicalURL)", level: 0, context: nil)
        return bundle
    }

    public func uninstallAdapter(id: String) async throws {
        let descriptor = FetchDescriptor<InstalledAdapterEntity>(
            predicate: #Predicate { $0.id == id }
        )
        let entities = try modelContext.fetch(descriptor)
        guard !entities.isEmpty else {
            throw AdapterStoreError.adapterNotFound(id)
        }
        for entity in entities {
            modelContext.delete(entity)
        }
        try modelContext.save()
    }

    public func listInstalledAdapters() async throws -> [AdapterBundle] {
        let descriptor = FetchDescriptor<InstalledAdapterEntity>(
            sortBy: [SortDescriptor(\.installedAt, order: .reverse)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toAdapterBundle() }
    }

    public func getInstalledAdapter(id: String) async throws -> AdapterBundle? {
        let descriptor = FetchDescriptor<InstalledAdapterEntity>(
            predicate: #Predicate { $0.id == id }
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.first?.toAdapterBundle()
    }

    // MARK: - Updates

    public func checkForUpdates() async throws -> [(adapter: AdapterBundle, update: ExtensionEntry)] {
        var updates: [(AdapterBundle, ExtensionEntry)] = []

        let installed = try await listInstalledAdapters()

        for adapter in installed {
            // Fetch index from source repository
            let index = try await fetchRepositoryIndex(from: adapter.sourceRepositoryURL)

            // Find entry for this adapter
            if let entry = index.extensions.first(where: { $0.id == adapter.id }),
                entry.version != adapter.version,
                AdapterVersion(entry.version) > AdapterVersion(adapter.version)
            {
                updates.append((adapter, entry))
            }
        }

        return updates
    }

    public func updateAdapter(id: String, to version: String) async throws -> AdapterBundle {
        let adapter = try await getInstalledAdapter(id: id)
        guard let adapter = adapter else {
            throw AdapterStoreError.adapterNotFound(id)
        }

        // Reject downgrades before uninstalling the current bundle.
        guard AdapterVersion(version) > AdapterVersion(adapter.version) else {
            throw AdapterStoreError.downgradeNotAllowed(
                id: id,
                installed: adapter.version,
                requested: version
            )
        }

        // Uninstall old version first
        try await uninstallAdapter(id: id)

        // Install new version
        return try await installAdapter(id: id, version: version, from: adapter.sourceRepositoryURL)
    }

    // MARK: - Helpers

    /// Keeps the underlying network cause visible to the UI and diagnostics.
    private nonisolated static func describedNetworkError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "\(urlError.localizedDescription) (URLError \(urlError.code.rawValue))"
        }
        return error.localizedDescription
    }

    /// Verifies and parses a downloaded bundle away from the main actor.
    ///
    /// SHA-256, Ed25519 verification and the regex-based manifest/selector
    /// extraction are CPU work; running them on the main actor stalls the UI
    /// during installs and updates.
    private nonisolated static func verifyBundle(
        _ bundleData: Data,
        entry: ExtensionEntry,
        publicKeyString: String
    ) async throws -> (manifest: AdapterManifest, selectors: ThemeSelectors) {
        try await Task.detached(priority: .userInitiated) {
            try SHA256Verifier.verify(bundleData, expectedHex: entry.sha256)

            let publicKey = try Ed25519Verifier.extractPublicKey(from: publicKeyString)
            try Ed25519Verifier.verify(
                signatureBase64: entry.bundleSignature,
                data: bundleData,
                publicKey: publicKey
            )

            let inspected = try inspectBundle(bundleData, sha256: entry.sha256)
            let manifest = inspected.manifest

            guard manifest.id == entry.id else {
                throw AdapterStoreError.bundleVerificationFailed(
                    "Manifest ID mismatch: expected \(entry.id), got \(manifest.id)")
            }
            guard manifest.version == entry.version else {
                throw AdapterStoreError.bundleVerificationFailed(
                    "Manifest version mismatch: expected \(entry.version), got \(manifest.version)")
            }
            guard manifest.apiVersion == entry.apiVersion else {
                throw AdapterStoreError.bundleVerificationFailed(
                    "API version mismatch: expected \(entry.apiVersion), got \(manifest.apiVersion)")
            }
            guard manifest.sha256 == entry.sha256 else {
                throw AdapterStoreError.bundleVerificationFailed("Manifest SHA-256 mismatch")
            }

            return (manifest, inspected.selectors)
        }.value
    }

    private func repositoryRequestHandler(for urlString: String) throws -> PluginRequestHandler {
        guard
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased()
        else {
            throw AdapterStoreError.invalidRepositoryURL
        }

        return PluginRequestHandler(
            policy: SiteNetworkPolicy(
                baseURL: urlString,
                allowedHosts: [host],
                maxRedirects: 3,
                cookieHandling: .none,
                timeout: 30,
                maxResponseBytes: 25 * 1024 * 1024
            ),
            logger: ConsolePluginLogger()
        )
    }

    private func resolveBundleURL(_ bundleURL: String, baseURL: String) -> String {
        if bundleURL.hasPrefix("http://") || bundleURL.hasPrefix("https://") {
            return bundleURL
        }
        guard let base = URL(string: baseURL), let resolved = URL(string: bundleURL, relativeTo: base) else {
            return bundleURL
        }
        return resolved.absoluteString
    }

    /// Evaluates a verified adapter bundle and decodes its public fields.
    ///
    /// The bundle is an esbuild IIFE, so field extraction cannot rely on a
    /// regular expression. The signature and hash have already been verified
    /// before this runs; the temporary context is discarded immediately.
    ///
    /// Not private so the bundle shape is covered by a unit test.
    nonisolated static func inspectBundle(
        _ bundleData: Data,
        sha256: String
    ) throws -> (manifest: AdapterManifest, selectors: ThemeSelectors) {
        let script = String(decoding: bundleData, as: UTF8.self)
        guard let context = JSContext() else {
            throw AdapterStoreError.bundleVerificationFailed(
                "Could not create a JavaScript context for the adapter bundle")
        }

        context.exception = nil
        _ = context.evaluateScript(script, withSourceURL: URL(fileURLWithPath: "adapter.js"))
        if let exception = context.exception {
            throw AdapterStoreError.bundleVerificationFailed(
                "Adapter bundle failed to evaluate: \(exception.toString() ?? "unknown error")")
        }

        guard
            let exports = context.objectForKeyedSubscript("BlankGrimoireRuntime"),
            exports.isObject
        else {
            throw AdapterStoreError.bundleVerificationFailed(
                "The adapter bundle does not expose a BlankGrimoireRuntime global")
        }

        let adapter: JSValue
        if let value = exports.objectForKeyedSubscript("default"), value.isObject {
            adapter = value
        } else if let value = exports.objectForKeyedSubscript("adapter"), value.isObject {
            adapter = value
        } else if let id = exports.objectForKeyedSubscript("id"), id.isString {
            adapter = exports
        } else {
            throw AdapterStoreError.bundleVerificationFailed("Missing default adapter export")
        }

        guard
            let stringify = context.objectForKeyedSubscript("JSON")?
                .objectForKeyedSubscript("stringify"),
            let json = stringify.call(withArguments: [adapter])?.toString(),
            let jsonData = json.data(using: .utf8)
        else {
            throw AdapterStoreError.bundleVerificationFailed(
                "Could not serialise the adapter bundle")
        }

        let inspection: AdapterBundleInspection
        do {
            inspection = try JSONDecoder().decode(AdapterBundleInspection.self, from: jsonData)
        } catch {
            throw AdapterStoreError.bundleVerificationFailed(
                "Invalid adapter bundle: \(error.localizedDescription)")
        }

        let manifest = AdapterManifest(
            id: inspection.id,
            name: inspection.name ?? inspection.id,
            version: inspection.version,
            apiVersion: inspection.apiVersion,
            detectionSignature: inspection.detectionSignature,
            sha256: sha256,
            referrerHeaders: inspection.referrerHeaders ?? [:]
        )
        return (manifest, inspection.selectors)
    }
}

// MARK: - SwiftData Entities

/// SwiftData entity for trusted repositories.
@Model
public final class TrustedRepositoryEntity {
    @Attribute(.unique) public var url: String
    public var name: String
    public var publicKey: String
    public var trustedAt: Date
    public var lastVerifiedAt: Date?

    public init(trusted: TrustedRepository) {
        self.url = trusted.url
        self.name = trusted.name
        self.publicKey = trusted.publicKey
        self.trustedAt = trusted.trustedAt
        self.lastVerifiedAt = trusted.lastVerifiedAt
    }

    public func toTrustedRepository() -> TrustedRepository {
        var repo = TrustedRepository(
            url: url,
            name: name,
            publicKey: publicKey,
            trustedAt: trustedAt
        )
        repo.lastVerifiedAt = lastVerifiedAt
        return repo
    }
}

/// SwiftData entity for installed adapters.
@Model
public final class InstalledAdapterEntity {
    @Attribute(.unique) public var id: String
    public var name: String
    public var version: String
    public var apiVersion: Int
    public var detectionSignature: ThemeSignature
    public var themeSelectors: ThemeSelectors
    public var sha256: String
    @Attribute(.externalStorage) public var bundleData: Data
    public var sourceRepositoryURL: String
    public var installedAt: Date
    /// Theme-declared CDN referrer map, stored as JSON so a restart keeps it.
    /// Optional so existing stores migrate without losing installed adapters.
    public var referrerHeadersJSON: String?

    public init(bundle: AdapterBundle) {
        self.id = bundle.id
        self.name = bundle.themeAdapter.name
        self.version = bundle.themeAdapter.version
        self.apiVersion = bundle.manifest.apiVersion
        self.detectionSignature = bundle.themeAdapter.detectionSignature
        self.themeSelectors = bundle.themeAdapter.selectors
        self.sha256 = bundle.manifest.sha256
        self.bundleData = bundle.bundleData
        self.sourceRepositoryURL = bundle.sourceRepositoryURL
        self.installedAt = bundle.installedAt
        self.referrerHeadersJSON = Self.encodeReferrerHeaders(bundle.themeAdapter.referrerHeaders)
    }

    public func toAdapterBundle() -> AdapterBundle {
        let referrerHeaders = Self.decodeReferrerHeaders(referrerHeadersJSON)
        let manifest = AdapterManifest(
            id: id,
            name: name,
            version: version,
            apiVersion: apiVersion,
            detectionSignature: detectionSignature,
            sha256: sha256,
            referrerHeaders: referrerHeaders
        )
        let themeAdapter = ThemeAdapter(
            id: id,
            name: name,
            version: version,
            detectionSignature: detectionSignature,
            selectors: themeSelectors,
            referrerHeaders: referrerHeaders
        )
        return AdapterBundle(
            manifest: manifest,
            themeAdapter: themeAdapter,
            bundleData: bundleData,
            sourceRepositoryURL: sourceRepositoryURL,
            installedAt: installedAt
        )
    }

    private static func encodeReferrerHeaders(_ headers: [String: String]) -> String? {
        guard !headers.isEmpty,
            let data = try? JSONEncoder().encode(headers)
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeReferrerHeaders(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
            let headers = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return headers
    }
}

// MARK: - Preview/Testing Support

#if DEBUG
    extension DefaultAdapterStore {
        /// Creates an in-memory adapter store for testing.
        public static func createInMemory() throws -> DefaultAdapterStore {
            let container = try BlankGrimoireSchema.makeContainer(
                isStoredInMemoryOnly: true,
                name: "AdapterStoreTest"
            )
            return try DefaultAdapterStore(modelContainer: container)
        }

        /// Test helper: directly inserts an installed adapter entity.
        public func insertInstalledAdapterForTesting(_ entity: InstalledAdapterEntity) async throws {
            modelContext.insert(entity)
            try modelContext.save()
        }

        /// Test helper: directly inserts a trusted repository entity.
        public func insertTrustedRepositoryForTesting(_ entity: TrustedRepositoryEntity) async throws {
            modelContext.insert(entity)
            try modelContext.save()
        }
    }
#endif
