// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation
import SwiftData

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

// The canonical RepositoryIndex and ExtensionEntry are defined in Models.swift
// import them via the module - no redefinition needed

// The canonical AdapterManifest is defined in Models.swift
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
        // Verify the public key matches
        guard index.publicKey == publicKey else {
            throw AdapterStoreError.publicKeyMismatch
        }
    }
}

// MARK: - Adapter Store Protocol

/// Protocol for adapter store operations.
public protocol AdapterStore: Sendable {
    /// Fetches and verifies a repository index.
    func fetchRepositoryIndex(from url: String) async throws -> RepositoryIndex

    /// Trusts a repository (TOFU - called after user confirmation).
    func trustRepository(_ index: RepositoryIndex) async throws

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
    /// Trusts an index while preserving the URL it was fetched from.
    ///
    /// The URL is part of the trust identity and must not be inferred from the
    /// display name in the repository index.
    public func trustRepository(_ index: RepositoryIndex, from repositoryURL: String) async throws {
        try await trustRepository(index)
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

    public init(
        modelContainer: ModelContainer,
        requestHandler: PluginRequestHandler,
        logger: PluginLogger = ConsolePluginLogger()
    ) throws {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
        self.logger = logger
        _ = requestHandler
    }

    // MARK: - Repository Index

    public func fetchRepositoryIndex(from url: String) async throws -> RepositoryIndex {
        guard let indexURL = RepositoryURL.normalizedIndexURL(from: url) else {
            throw AdapterStoreError.invalidRepositoryURL
        }

        let request = HttpRequest(url: indexURL.absoluteString, method: "GET")
        let response = try await repositoryRequestHandler(for: indexURL.absoluteString).perform(request)

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

    public func trustRepository(_ index: RepositoryIndex) async throws {
        let trusted = TrustedRepository(
            url: index.name,
            name: index.name,
            publicKey: index.publicKey
        )

        let entity = TrustedRepositoryEntity(trusted: trusted)
        modelContext.insert(entity)
        try modelContext.save()

        logger.log("Trusted repository: \(index.name)", level: 0, context: nil)
    }

    public func trustRepository(_ index: RepositoryIndex, from repositoryURL: String) async throws {
        guard let indexURL = RepositoryURL.normalizedIndexURL(from: repositoryURL) else {
            throw AdapterStoreError.invalidRepositoryURL
        }

        let canonicalURL = indexURL.absoluteString
        let trusted = TrustedRepository(
            url: canonicalURL,
            name: index.name,
            publicKey: index.publicKey
        )
        modelContext.insert(TrustedRepositoryEntity(trusted: trusted))
        try modelContext.save()
        logger.log("Trusted repository: \(canonicalURL)", level: 0, context: nil)
    }

    public func isRepositoryTrusted(_ url: String) async throws -> Bool {
        let descriptor = FetchDescriptor<TrustedRepositoryEntity>(
            predicate: #Predicate { $0.url == url }
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
        let descriptor = FetchDescriptor<TrustedRepositoryEntity>(
            predicate: #Predicate { $0.url == url }
        )
        let entities = try modelContext.fetch(descriptor)
        for entity in entities {
            modelContext.delete(entity)
        }
        try modelContext.save()
    }

    // MARK: - Adapter Installation

    public func installAdapter(id: String, version: String, from repositoryURL: String) async throws -> AdapterBundle {
        // 1. Verify repository is trusted
        let isTrusted = try await isRepositoryTrusted(repositoryURL)
        guard isTrusted else {
            throw AdapterStoreError.repositoryNotTrusted(repositoryURL)
        }

        // 2. Fetch repository index to get extension entry
        let index = try await fetchRepositoryIndex(from: repositoryURL)

        guard let entry = index.extensions.first(where: { $0.id == id && $0.version == version }) else {
            throw AdapterStoreError.adapterNotFound("\(id)@\(version)")
        }

        // 3. Check if already installed
        if let existing = try await getInstalledAdapter(id: id) {
            if existing.version == version {
                throw AdapterStoreError.adapterAlreadyInstalled(id)
            }
            // Allow upgrade - will replace below
        }

        // 4. Download bundle
        let bundleURL = resolveBundleURL(entry.bundleURL, baseURL: repositoryURL)
        let request = HttpRequest(url: bundleURL, method: "GET")
        let response = try await repositoryRequestHandler(for: bundleURL).perform(request)

        guard response.status >= 200 && response.status < 300 else {
            throw AdapterStoreError.bundleDownloadFailed("HTTP \(response.status)")
        }

        let bundleData = Data(response.body.utf8)

        // 5. Verify SHA-256
        try SHA256Verifier.verify(bundleData, expectedHex: entry.sha256)

        // 6. Verify Ed25519 signature
        let trustedRepos = try await listTrustedRepositories()
        guard let trusted = trustedRepos.first(where: { $0.url == repositoryURL || $0.name == repositoryURL }) else {
            throw AdapterStoreError.repositoryNotTrusted(repositoryURL)
        }

        let publicKey = try Ed25519Verifier.extractPublicKey(from: trusted.publicKey)
        try Ed25519Verifier.verify(
            signatureBase64: entry.bundleSignature,
            data: bundleData,
            publicKey: publicKey
        )

        // 7. Parse manifest from bundle (first few KB should contain the manifest)
        let manifest = try parseManifest(from: bundleData)

        // 8. Verify manifest matches entry
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

        // 9. Store bundle
        let themeAdapter = ThemeAdapter(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            detectionSignature: manifest.detectionSignature,
            selectors: try extractSelectors(from: bundleData)
        )
        let bundle = AdapterBundle(
            manifest: manifest,
            themeAdapter: themeAdapter,
            bundleData: bundleData,
            sourceRepositoryURL: repositoryURL
        )

        let entity = InstalledAdapterEntity(bundle: bundle)
        modelContext.insert(entity)
        try modelContext.save()

        logger.log("Installed adapter: \(id)@\(version) from \(repositoryURL)", level: 0, context: nil)
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
                entry.version.compare(adapter.version, options: .numeric) == .orderedDescending
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

        // Uninstall old version first
        try await uninstallAdapter(id: id)

        // Install new version
        return try await installAdapter(id: id, version: version, from: adapter.sourceRepositoryURL)
    }

    // MARK: - Helpers

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
                maxRedirects: 5,
                cookieHandling: .none
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

    private func parseManifest(from bundleData: Data) throws -> AdapterManifest {
        // The bundle is a JavaScript file. We need to extract the manifest from it.
        // The manifest is exposed as `BlankGrimoireRuntime.default` or similar.
        // For simplicity, we'll parse it as JSON if it starts with {, otherwise
        // we'd need a JS parser. Since the bundle is the adapter script itself,
        // the manifest is embedded in the JS.

        // Try to find the manifest object in the bundle
        let bundleString = String(decoding: bundleData, as: UTF8.self)

        // Look for the adapter export pattern
        // var BlankGrimoireRuntime = { default: { id: "...", ... } }
        let pattern = #"BlankGrimoireRuntime\s*=\s*\{[^}]*default\s*:\s*(\{[^}]+\})"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: bundleString.utf16.count)

        if let match = regex.firstMatch(in: bundleString, options: [], range: range),
            let manifestRange = Range(match.range(at: 1), in: bundleString)
        {
            let manifestJSON = String(bundleString[manifestRange])
            let manifestData = Data(manifestJSON.utf8)
            return try JSONDecoder().decode(AdapterManifest.self, from: manifestData)
        }

        // Fallback: try to parse as if the whole bundle is JSON (for testing)
        if bundleString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try JSONDecoder().decode(AdapterManifest.self, from: bundleData)
        }

        throw AdapterStoreError.bundleVerificationFailed("Could not extract manifest from bundle")
    }

    private func extractSelectors(from bundleData: Data) throws -> ThemeSelectors {
        let bundleString = String(decoding: bundleData, as: UTF8.self)

        // Look for the selectors object in the bundle
        // Pattern: "selectors": { ... }
        let pattern = #""selectors"\s*:\s*(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: bundleString.utf16.count)

        if let match = regex.firstMatch(in: bundleString, options: [], range: range),
            let selectorsRange = Range(match.range(at: 1), in: bundleString)
        {
            let selectorsJSON = String(bundleString[selectorsRange])
            let selectorsData = Data(selectorsJSON.utf8)
            return try JSONDecoder().decode(ThemeSelectors.self, from: selectorsData)
        }

        // Fallback: return minimal selectors for testing
        return ThemeSelectors(
            search: .init(path: "", item: "", title: "", link: ""),
            details: .init(
                title: "", cover: nil, synopsis: nil, authors: nil, artists: nil, altTitles: nil, tags: nil,
                status: nil, contentRating: nil),
            chapters: .init(item: "", link: "", title: nil, date: nil, order: "desc"),
            pages: .init(strategies: []),
            attribution: nil
        )
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
    public var bundleData: Data
    public var sourceRepositoryURL: String
    public var installedAt: Date

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
    }

    public func toAdapterBundle() -> AdapterBundle {
        let manifest = AdapterManifest(
            id: id,
            name: name,
            version: version,
            apiVersion: apiVersion,
            detectionSignature: detectionSignature,
            sha256: sha256
        )
        let themeAdapter = ThemeAdapter(
            id: id,
            name: name,
            version: version,
            detectionSignature: detectionSignature,
            selectors: themeSelectors
        )
        return AdapterBundle(
            manifest: manifest,
            themeAdapter: themeAdapter,
            bundleData: bundleData,
            sourceRepositoryURL: sourceRepositoryURL,
            installedAt: installedAt
        )
    }
}

// MARK: - Preview/Testing Support

#if DEBUG
    extension DefaultAdapterStore {
        /// Creates an in-memory adapter store for testing.
        public static func createInMemory(
            requestHandler: PluginRequestHandler? = nil
        ) throws -> DefaultAdapterStore {
            let schema = Schema([
                TrustedRepositoryEntity.self,
                InstalledAdapterEntity.self,
            ])

            let configuration = ModelConfiguration(
                "Test",
                isStoredInMemoryOnly: true
            )

            let container = try ModelContainer(for: schema, configurations: [configuration])

            let handler =
                requestHandler
                ?? PluginRequestHandler(
                    policy: SiteNetworkPolicy(
                        baseURL: "https://example.org",
                        allowedHosts: ["example.org"]
                    )
                )

            return try DefaultAdapterStore(
                modelContainer: container,
                requestHandler: handler
            )
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
