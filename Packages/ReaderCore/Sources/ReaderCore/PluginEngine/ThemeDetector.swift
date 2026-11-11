// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftSoup

/// Errors that can occur during theme detection.
public enum ThemeDetectorError: Error, LocalizedError, Sendable, Equatable {
    case noThemeMatched
    case multipleThemesMatched([String])
    case invalidURL(String)
    case invalidHTML(String)
    case fetchFailed(String)
    case probeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noThemeMatched:
            return "No theme matched the site"
        case .multipleThemesMatched(let ids):
            return "Multiple themes matched: \(ids.joined(separator: ", "))"
        case .invalidURL(let value):
            return "Invalid site URL: \(value)"
        case .invalidHTML(let msg):
            return "Invalid HTML for detection: \(msg)"
        case .fetchFailed(let msg):
            return "Failed to fetch probe page: \(msg)"
        case .probeFailed(let msg):
            return "Probe failed: \(msg)"
        }
    }
}

/// Result of theme detection.
public struct ThemeDetectionResult: Sendable, Equatable {
    public let theme: ThemeAdapter
    public let score: Int
    public let matchedSignals: [String]

    public init(theme: ThemeAdapter, score: Int, matchedSignals: [String]) {
        self.theme = theme
        self.score = score
        self.matchedSignals = matchedSignals
    }
}

/// Detects the appropriate theme for a given site by analyzing HTML content
/// and probing known paths.
///
/// Ties are resolved deterministically. When two adapters score the same, the
/// detector prefers the higher `minScore`, then the adapter with more
/// selectors, then the lexicographically smaller adapter id. Probe paths refine
/// the score before the final tie-break runs.
public actor ThemeDetector {
    private struct ScoredAdapter {
        let adapter: ThemeAdapter
        let score: Int
        let signals: [String]
    }

    private let adapterStore: any AdapterStore
    private let requestHandler: PluginRequestHandler
    private let logger: PluginLogger
    private var regexCache: [String: NSRegularExpression] = [:]
    private var invalidPatterns: Set<String> = []

    public init(
        adapterStore: any AdapterStore,
        requestHandler: PluginRequestHandler,
        logger: PluginLogger = ConsolePluginLogger()
    ) {
        self.adapterStore = adapterStore
        self.requestHandler = requestHandler
        self.logger = logger
    }

    /// Detects the best matching theme for a site by:
    /// 1. Fetching the main page
    /// 2. Scoring installed adapters against the page
    /// 3. Probing additional paths if needed
    /// 4. Returning the highest-scoring adapter above minScore
    public func detectTheme(for url: String) async throws -> ThemeDetectionResult {
        guard Self.isValidSiteURL(url) else {
            throw ThemeDetectorError.invalidURL(url)
        }

        let mainPageHTML = try await fetchPage(url)
        return try await detectTheme(from: mainPageHTML, baseURL: url)
    }

    /// Detects theme with a pre-fetched HTML (for testing or when page is already loaded).
    public func detectTheme(from html: String, baseURL: String) async throws -> ThemeDetectionResult {
        guard Self.isValidSiteURL(baseURL) else {
            throw ThemeDetectorError.invalidURL(baseURL)
        }

        let installedAdapters = try await adapterStore.listInstalledAdapters()
        guard !installedAdapters.isEmpty else {
            throw ThemeDetectorError.noThemeMatched
        }

        let document: Document
        do {
            document = try SwiftSoup.parse(html)
        } catch {
            throw ThemeDetectorError.invalidHTML(error.localizedDescription)
        }

        var scoredAdapters: [ScoredAdapter] = []

        for bundle in installedAdapters {
            let adapter = bundle.themeAdapter
            let (score, signals) = scoreAdapter(adapter, against: document)
            if score >= adapter.detectionSignature.minScore {
                scoredAdapters.append(
                    ScoredAdapter(adapter: adapter, score: score, signals: signals)
                )
            }
        }

        scoredAdapters.sort(by: precedes)

        guard let best = scoredAdapters.first else {
            throw ThemeDetectorError.noThemeMatched
        }

        let tied = scoredAdapters.filter { $0.score == best.score }
        if tied.count > 1 {
            let resolved = await resolveTie(tied, baseURL: baseURL)
            return ThemeDetectionResult(
                theme: resolved.adapter,
                score: resolved.score,
                matchedSignals: resolved.signals
            )
        }

        return ThemeDetectionResult(
            theme: best.adapter,
            score: best.score,
            matchedSignals: best.signals
        )
    }

    // MARK: - Private

    private static func isValidSiteURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty
        else {
            return false
        }
        return true
    }

    private func fetchPage(_ url: String) async throws -> String {
        let request = HttpRequest(url: url, method: "GET")
        let response = try await requestHandler.perform(request)

        guard response.status >= 200 && response.status < 300 else {
            throw ThemeDetectorError.fetchFailed("HTTP \(response.status)")
        }

        return response.body
    }

    private func regex(for pattern: String) throws -> NSRegularExpression {
        if let cached = regexCache[pattern] {
            return cached
        }
        let compiled = try NSRegularExpression(pattern: pattern)
        regexCache[pattern] = compiled
        return compiled
    }

    /// Returns whether the pattern matches. Invalid patterns are reported once
    /// and treated as non-matching so one bad remote adapter cannot invalidate
    /// the score of an otherwise healthy adapter.
    private func matches(_ pattern: String, in value: String) -> Bool {
        do {
            let expression = try regex(for: pattern)
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return expression.firstMatch(in: value, options: [], range: range) != nil
        } catch {
            if invalidPatterns.insert(pattern).inserted {
                logger.warn(
                    "Ignoring invalid detection regex: \(pattern)",
                    level: 1,
                    context: nil
                )
            }
            return false
        }
    }

    private func scoreAdapter(_ adapter: ThemeAdapter, against document: Document) -> (Int, [String]) {
        var score = 0
        var signals: [String] = []

        let signature = adapter.detectionSignature

        do {
            // 1. Check meta generator
            if let metaGenerator = signature.metaGenerator,
                !metaGenerator.isEmpty
            {
                if let generator = try document.select("meta[name=generator]").first() {
                    let content = try generator.attr("content")
                    if matches(metaGenerator, in: content) {
                        score += 30
                        signals.append("metaGenerator")
                    }
                }
            }

            // 2. Check CSS selectors
            if let selectors = signature.selectors {
                for selector in selectors {
                    let elements = try document.select(selector)
                    if !elements.isEmpty() {
                        score += 15
                        signals.append("selector:\(selector)")
                    }
                }
            }

            // 3. Check script src patterns. Score once per declared pattern,
            // not once per matching script element.
            if let scriptPatterns = signature.scriptSrc {
                let scripts = try document.select("script[src]")
                for pattern in scriptPatterns {
                    var matched = false
                    for script in scripts.array() {
                        let src = try script.attr("src")
                        if matches(pattern, in: src) {
                            matched = true
                            break
                        }
                    }
                    if matched {
                        score += 20
                        signals.append("scriptSrc:\(pattern)")
                    }
                }
            }

        } catch {
            logger.error(
                "Failed to score adapter \(adapter.id): \(error.localizedDescription)",
                level: 2,
                context: nil
            )
        }

        return (score, signals)
    }

    /// Applies the documented tie-break order. It is also the final ordering
    /// for non-tied adapters, which keeps the result stable across store order.
    private func precedes(_ lhs: ScoredAdapter, _ rhs: ScoredAdapter) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        let lhsMinScore = lhs.adapter.detectionSignature.minScore
        let rhsMinScore = rhs.adapter.detectionSignature.minScore
        if lhsMinScore != rhsMinScore {
            return lhsMinScore > rhsMinScore
        }

        let lhsSelectors = lhs.adapter.detectionSignature.selectors?.count ?? 0
        let rhsSelectors = rhs.adapter.detectionSignature.selectors?.count ?? 0
        if lhsSelectors != rhsSelectors {
            return lhsSelectors > rhsSelectors
        }

        return lhs.adapter.id < rhs.adapter.id
    }

    private func resolveTie(_ tied: [ScoredAdapter], baseURL: String) async -> ScoredAdapter {
        var resolved: [ScoredAdapter] = []

        for candidate in tied {
            var totalScore = candidate.score
            var allSignals = candidate.signals

            for path in candidate.adapter.detectionSignature.probePaths ?? [] {
                let probeURL = resolveProbeURL(path, baseURL: baseURL)
                do {
                    let probeHTML = try await fetchPage(probeURL)
                    let probeDocument = try SwiftSoup.parse(probeHTML)
                    let (probeScore, probeSignals) = scoreAdapter(
                        candidate.adapter,
                        against: probeDocument
                    )
                    totalScore += probeScore
                    allSignals.append(contentsOf: probeSignals)
                } catch {
                    logger.warn(
                        "Theme probe failed for \(candidate.adapter.id) at \(probeURL): \(error.localizedDescription)",
                        level: 1,
                        context: nil
                    )
                }
            }

            resolved.append(
                ScoredAdapter(adapter: candidate.adapter, score: totalScore, signals: allSignals)
            )
        }

        resolved.sort(by: precedes)
        return resolved[0]
    }

    private func resolveProbeURL(_ path: String, baseURL: String) -> String {
        guard let base = URL(string: baseURL), let resolved = URL(string: path, relativeTo: base) else {
            return baseURL + path
        }
        return resolved.absoluteString
    }
}
