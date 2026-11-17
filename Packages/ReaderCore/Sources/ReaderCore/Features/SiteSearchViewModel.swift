// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// Cross-site search and import flow.
///
/// The user types a title (or a filter) once and the app queries every
/// enabled site profile that is stored locally. Results are grouped by
/// site, and each row can be imported into the library together with its
/// chapter list.
@MainActor
@Observable
public final class SiteSearchViewModel {
    public var query: String = ""
    /// Sites included in the next search. Every enabled site starts
    /// selected; the user unchecks the ones to leave out.
    public var selectedSiteIDs: Set<String> = []
    public var selectedGenre: String? = nil
    /// Extracted from the enabled sites when the screen loads. Starts empty
    /// on purpose: the app never ships or restores a built-in genre list.
    public private(set) var unifiedGenres: [UnifiedGenre] = []
    public var sites: [SiteProfile] = []
    public private(set) var results: [SiteSearchResult] = []
    public private(set) var failures: [SiteSearchFailure] = []
    public private(set) var isSearching = false
    public private(set) var isLoadingMore = false
    public private(set) var hasSearched = false
    /// Whether the last site page announced another result page.
    public private(set) var hasMoreResults = false
    public private(set) var importingIDs: Set<String> = []
    public private(set) var importedIDs: Set<String> = []
    public var lastError: Error?

    private let siteProfileRepository: any SiteProfileRepository
    private let catalogService: (any SiteCatalogProviding)?
    private let mangaRepository: (any MangaRepository)?
    /// Incremented on every search so stale results from a superseded
    /// request cannot overwrite the latest one.
    private var searchGeneration = 0
    /// Cursors for the next page, keyed by site profile id.
    private var nextPageURLs: [String: String] = [:]
    /// Whether the initial "every enabled site is selected" state was
    /// applied. Without it, clearing the selection would look like a fresh
    /// load and select everything again.
    private var didInitialiseSiteSelection = false

    public init(
        siteProfileRepository: any SiteProfileRepository,
        catalogService: (any SiteCatalogProviding)?,
        mangaRepository: (any MangaRepository)? = nil
    ) {
        self.siteProfileRepository = siteProfileRepository
        self.catalogService = catalogService
        self.mangaRepository = mangaRepository
    }

    /// True when the composition root supplied a catalog service.
    public var isAvailable: Bool {
        catalogService != nil
    }

    /// URL the visible verification browser must open, when the last
    /// operation was stopped by a site challenge.
    public var challengeURL: URL? {
        guard let error = lastError as? SiteBrowsingError else { return nil }
        if case .challengeRequired(let url) = error {
            return url
        }
        return nil
    }

    /// Sites that can receive the next search.
    public var searchableSites: [SiteProfile] {
        sites.filter(\.isEnabled)
    }

    public var targetSites: [SiteProfile] {
        searchableSites.filter { selectedSiteIDs.contains($0.id) }
    }

    public func isSiteSelected(_ site: SiteProfile) -> Bool {
        selectedSiteIDs.contains(site.id)
    }

    /// Includes or excludes a site from the next search.
    public func setSite(_ site: SiteProfile, selected: Bool) {
        if selected {
            selectedSiteIDs.insert(site.id)
        } else {
            selectedSiteIDs.remove(site.id)
        }
    }

    public func toggleSite(_ site: SiteProfile) {
        setSite(site, selected: !isSiteSelected(site))
    }

    /// Every enabled site is selected, so the header action offers "none".
    public var areAllSitesSelected: Bool {
        !searchableSites.isEmpty && targetSites.count == searchableSites.count
    }

    public func setAllSitesSelected(_ selected: Bool) {
        selectedSiteIDs = selected ? Set(searchableSites.map(\.id)) : []
    }

    public func loadSites() async {
        do {
            sites = try await siteProfileRepository.fetchAll()

            let enabledIDs = Set(sites.filter(\.isEnabled).map(\.id))
            if didInitialiseSiteSelection {
                // Profiles can be deleted or disabled: drop stale ids but
                // keep an empty selection empty.
                selectedSiteIDs.formIntersection(enabledIDs)
            } else {
                selectedSiteIDs = enabledIDs
                didInitialiseSiteSelection = true
            }

            await loadUnifiedGenres()
        } catch {
            lastError = error
        }
    }

    /// Rebuilds the genre list for the currently selected sites.
    public func reloadGenres() async {
        await loadUnifiedGenres()
    }

    private func loadUnifiedGenres() async {
        guard let catalogService else { return }
        let enabled = targetSites
        guard !enabled.isEmpty else {
            unifiedGenres = []
            return
        }
        unifiedGenres = await catalogService.fetchUnifiedGenres(for: enabled)
        if let sel = selectedGenre, !unifiedGenres.contains(where: { $0.id == sel.lowercased() }) {
            selectedGenre = nil
        }
    }

    public func search() async {
        guard let catalogService else {
            lastError = SiteBrowsingError.catalogUnavailable
            return
        }

        await loadSites()

        let searchQuery = SearchQuery(
            text: query.trimmingCharacters(in: .whitespacesAndNewlines),
            page: 1,
            genres: selectedGenre.map { [$0] })
        guard !searchQuery.text!.isEmpty || !(searchQuery.genres?.isEmpty ?? true) else {
            results = []
            failures = []
            hasSearched = false
            hasMoreResults = false
            nextPageURLs = [:]
            return
        }

        let targets = targetSites
        guard !targets.isEmpty else {
            results = []
            failures = []
            hasSearched = true
            hasMoreResults = false
            nextPageURLs = [:]
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        lastError = nil
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        let genre = selectedGenre.flatMap { id in
            unifiedGenres.first { $0.id == id }
        }
        let genreValues =
            genre.map { genre in
                Dictionary(uniqueKeysWithValues: genre.siteFilters.map { ($0.key, $0.value.value) })
            } ?? [:]

        let outcome = await catalogService.search(searchQuery, in: targets, genreValues: genreValues)
        guard generation == searchGeneration, !Task.isCancelled else { return }
        results = outcome.results
        failures = outcome.failures
        nextPageURLs = outcome.nextPageURLs
        hasMoreResults = outcome.hasMore
        hasSearched = true
        if let challengeURL = outcome.challengeURL {
            lastError = SiteBrowsingError.challengeRequired(challengeURL)
        }
        await refreshImportedIDs()
    }

    /// Loads the next result page and appends it to the current list.
    ///
    /// Each site exposes its own "next" link, so the catalog returns the
    /// new cursor alongside the new results.
    public func loadMore() async {
        guard let catalogService, !isSearching, !isLoadingMore, hasMoreResults,
            !nextPageURLs.isEmpty
        else {
            return
        }

        let searchQuery = SearchQuery(
            text: query.trimmingCharacters(in: .whitespacesAndNewlines),
            page: 1,
            genres: selectedGenre.map { [$0] })
        guard !searchQuery.text!.isEmpty || !(searchQuery.genres?.isEmpty ?? true) else { return }

        let outcome = SiteSearchOutcome(
            results: results,
            failures: failures,
            nextPageURLs: nextPageURLs
        )
        let generation = searchGeneration
        isLoadingMore = true
        lastError = nil
        defer {
            if generation == searchGeneration {
                isLoadingMore = false
            }
        }

        let next = await catalogService.searchNextPage(
            query: searchQuery,
            in: targetSites,
            continuingFrom: outcome
        )
        guard generation == searchGeneration, !Task.isCancelled else { return }

        var seen = Set(results.map(\.id))
        results.append(contentsOf: next.results.filter { seen.insert($0.id).inserted })
        var failedSites = Set(failures.map(\.siteProfileID))
        failures.append(contentsOf: next.failures.filter { failedSites.insert($0.siteProfileID).inserted })
        nextPageURLs = next.nextPageURLs
        hasMoreResults = next.hasMore
        if let challengeURL = next.challengeURL {
            lastError = SiteBrowsingError.challengeRequired(challengeURL)
        }
        await refreshImportedIDs()
    }

    /// Rebuilds the "already in library" state from persisted data so it
    /// survives a new view model or an app relaunch.
    private func refreshImportedIDs() async {
        guard let mangaRepository, !results.isEmpty else { return }
        do {
            let imported = try await mangaRepository.fetchByIds(results.map(\.id))
            importedIDs = Set(imported.map(\.id))
        } catch {
            lastError = error
        }
    }

    public func importResult(_ result: SiteSearchResult) async {
        guard let catalogService else {
            lastError = SiteBrowsingError.catalogUnavailable
            return
        }
        guard !importingIDs.contains(result.id) else { return }

        importingIDs.insert(result.id)
        lastError = nil
        defer { importingIDs.remove(result.id) }

        do {
            _ = try await catalogService.importManga(result)
            importedIDs.insert(result.id)
        } catch {
            lastError = error
        }
    }

    public func reset() {
        searchGeneration += 1
        query = ""
        selectedGenre = nil
        unifiedGenres = []
        results = []
        failures = []
        nextPageURLs = [:]
        hasMoreResults = false
        hasSearched = false
        isSearching = false
        isLoadingMore = false
    }
}
