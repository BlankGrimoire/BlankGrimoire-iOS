// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftSoup

/// Errors that can occur during theme detection.
public enum ThemeDetectorError: Error, LocalizedError, Sendable, Equatable {
    case noThemeMatched
    case multipleThemesMatched([String])
    case invalidHTML(String)
    case fetchFailed(String)
    case probeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noThemeMatched:
            return "No theme matched the site"
        case .multipleThemesMatched(let ids):
            return "Multiple themes matched: \(ids.joined(separator: ", "))"
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
public actor ThemeDetector {
    private let adapterStore: any AdapterStore
    private let requestHandler: PluginRequestHandler
    private let logger: PluginLogger

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
        guard URL(string: url) != nil else {
            throw ThemeDetectorError.invalidHTML("Invalid URL: \(url)")
        }

        let installedAdapters = try await adapterStore.listInstalledAdapters()
        guard !installedAdapters.isEmpty else {
            throw ThemeDetectorError.noThemeMatched
        }

        // Fetch main page
        let mainPageHTML = try await fetchPage(url)

        // Score each adapter against the main page
        var scoredAdapters: [(ThemeAdapter, Int, [String])] = []

        for bundle in installedAdapters {
            let adapter = bundle.themeAdapter
            let (score, signals) = scoreAdapter(adapter, against: mainPageHTML, baseURL: url)
            if score >= adapter.detectionSignature.minScore {
                scoredAdapters.append((adapter, score, signals))
            }
        }

        // Sort by score descending
        scoredAdapters.sort { $0.1 > $1.1 }

        // If top score is tied, try probe paths
        if scoredAdapters.count >= 2 && scoredAdapters[0].1 == scoredAdapters[1].1 {
            let tiedAdapters = scoredAdapters.filter { $0.1 == scoredAdapters[0].1 }
            let resolved = try await resolveTie(tiedAdapters.map { $0.0 }, baseURL: url)
            if let resolved = resolved {
                return ThemeDetectionResult(theme: resolved.0, score: resolved.1, matchedSignals: resolved.2)
            }
        }

        guard let best = scoredAdapters.first else {
            throw ThemeDetectorError.noThemeMatched
        }

        return ThemeDetectionResult(theme: best.0, score: best.1, matchedSignals: best.2)
    }

    /// Detects theme with a pre-fetched HTML (for testing or when page is already loaded).
    public func detectTheme(from html: String, baseURL: String) async throws -> ThemeDetectionResult {
        let installedAdapters = try await adapterStore.listInstalledAdapters()
        guard !installedAdapters.isEmpty else {
            throw ThemeDetectorError.noThemeMatched
        }

        var scoredAdapters: [(ThemeAdapter, Int, [String])] = []

        for bundle in installedAdapters {
            let adapter = bundle.themeAdapter
            let (score, signals) = scoreAdapter(adapter, against: html, baseURL: baseURL)
            if score >= adapter.detectionSignature.minScore {
                scoredAdapters.append((adapter, score, signals))
            }
        }

        scoredAdapters.sort { $0.1 > $1.1 }

        guard let best = scoredAdapters.first else {
            throw ThemeDetectorError.noThemeMatched
        }

        return ThemeDetectionResult(theme: best.0, score: best.1, matchedSignals: best.2)
    }

    // MARK: - Private

    private func fetchPage(_ url: String) async throws -> String {
        let request = HttpRequest(url: url, method: "GET")
        let response = try await requestHandler.perform(request)

        guard response.status >= 200 && response.status < 300 else {
            throw ThemeDetectorError.fetchFailed("HTTP \(response.status)")
        }

        return response.body
    }

    private func scoreAdapter(
        _ adapter: ThemeAdapter,
        against html: String,
        baseURL: String
    ) -> (Int, [String]) {
        var score = 0
        var signals: [String] = []

        let signature = adapter.detectionSignature

        do {
            let document = try SwiftSoup.parse(html)

            // 1. Check meta generator
            if let metaGenerator = signature.metaGenerator,
                !metaGenerator.isEmpty
            {
                if let generator = try document.select("meta[name=generator]").first() {
                    let content = try generator.attr("content")
                    let regex = try NSRegularExpression(pattern: metaGenerator)
                    let range = NSRange(location: 0, length: content.utf16.count)
                    if regex.firstMatch(in: content, options: [], range: range) != nil {
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

            // 3. Check script src patterns
            if let scriptPatterns = signature.scriptSrc {
                for pattern in scriptPatterns {
                    let scripts = try document.select("script[src]")
                    for script in scripts.array() {
                        let src = try script.attr("src")
                        let regex = try NSRegularExpression(pattern: pattern)
                        let range = NSRange(location: 0, length: src.utf16.count)
                        if regex.firstMatch(in: src, options: [], range: range) != nil {
                            score += 20
                            signals.append("scriptSrc:\(pattern)")
                        }
                    }
                }
            }

        } catch {
            logger.error("Failed to parse HTML for detection: \(error)", level: 2, context: nil)
        }

        return (score, signals)
    }

    private func resolveTie(
        _ adapters: [ThemeAdapter],
        baseURL: String
    ) async throws -> (ThemeAdapter, Int, [String])? {
        // Probe additional paths for each tied adapter
        var bestScore = 0
        var bestAdapter: ThemeAdapter?
        var bestSignals: [String] = []

        for adapter in adapters {
            var totalScore = adapter.detectionSignature.minScore
            var allSignals: [String] = []

            if let probePaths = adapter.detectionSignature.probePaths {
                for path in probePaths {
                    let probeURL = resolveProbeURL(path, baseURL: baseURL)
                    do {
                        let probeHTML = try await fetchPage(probeURL)
                        let (probeScore, probeSignals) = scoreAdapter(adapter, against: probeHTML, baseURL: probeURL)
                        totalScore += probeScore
                        allSignals.append(contentsOf: probeSignals)
                    } catch {
                        // Probe failed, continue
                    }
                }
            }

            if totalScore > bestScore {
                bestScore = totalScore
                bestAdapter = adapter
                bestSignals = allSignals
            }
        }

        guard let adapter = bestAdapter else { return nil }
        return (adapter, bestScore, bestSignals)
    }

    private func resolveProbeURL(_ path: String, baseURL: String) -> String {
        guard let base = URL(string: baseURL), let resolved = URL(string: path, relativeTo: base) else {
            return baseURL + path
        }
        return resolved.absoluteString
    }
}
