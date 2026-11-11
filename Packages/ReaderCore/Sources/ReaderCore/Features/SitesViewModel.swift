// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// View model for sites management
@MainActor
@Observable
public final class SitesViewModel {
    public var siteProfiles: [SiteProfile] = []
    public var availableThemes: [ThemeAdapter] = []
    public var selectedThemeID: String = ""
    public var showingAddSite: Bool = false
    public var isLoading: Bool = false
    public var isDetecting: Bool = false
    public var lastDetection: ThemeDetectionResult?
    public var lastError: Error?

    /// URL that should be opened in the visible verification browser.
    public var challengeURL: URL? {
        guard let error = lastError as? ThemeDetectorError else { return nil }
        if case .challengeRequired(let url) = error {
            return url
        }
        return nil
    }

    private let siteProfileRepository: any SiteProfileRepository
    private let themeSource: any ThemeSource
    private let themeDetector: (any SiteThemeDetecting)?
    private let mangaRepository: (any MangaRepository)?
    private let chapterRepository: (any ChapterRepository)?
    private let pageRepository: (any PageRepository)?
    private let readingProgressRepository: (any ReadingProgressRepository)?
    private let bookmarkRepository: (any BookmarkRepository)?

    public init(
        siteProfileRepository: any SiteProfileRepository,
        themeSource: any ThemeSource,
        themeDetector: (any SiteThemeDetecting)? = nil,
        mangaRepository: (any MangaRepository)? = nil,
        chapterRepository: (any ChapterRepository)? = nil,
        pageRepository: (any PageRepository)? = nil,
        readingProgressRepository: (any ReadingProgressRepository)? = nil,
        bookmarkRepository: (any BookmarkRepository)? = nil
    ) {
        self.siteProfileRepository = siteProfileRepository
        self.themeSource = themeSource
        self.themeDetector = themeDetector
        self.mangaRepository = mangaRepository
        self.chapterRepository = chapterRepository
        self.pageRepository = pageRepository
        self.readingProgressRepository = readingProgressRepository
        self.bookmarkRepository = bookmarkRepository
    }

    public func loadProfiles() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            siteProfiles = try await siteProfileRepository.fetchAll()
            availableThemes = try await themeSource.listThemes()

            if !availableThemes.contains(where: { $0.id == selectedThemeID }) {
                selectedThemeID = availableThemes.first?.id ?? ""
            }
        } catch {
            lastError = error
        }
    }

    /// Validates and stores a new site profile.
    ///
    /// - Returns: `true` when the profile was saved, `false` when validation or
    ///   persistence failed (the error is exposed through `lastError`).
    public func addSite(url: String, name: String, themeID: String) async -> Bool {
        lastError = nil

        guard let baseURL = SiteURL.siteBaseURLString(from: url) else {
            lastError = SiteProfileError.invalidURL(url)
            return false
        }

        guard !themeID.isEmpty else {
            lastError = SiteProfileError.themeNotInstalled("(none selected)")
            return false
        }

        guard let theme = availableThemes.first(where: { $0.id == themeID }) else {
            lastError = SiteProfileError.themeNotInstalled(themeID)
            return false
        }

        do {
            let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = SiteProfile(
                name: displayName.isEmpty ? (SiteURL.host(from: baseURL) ?? baseURL) : displayName,
                baseURL: baseURL,
                themeID: theme.id,
                themeVersion: theme.version
            )
            // Check and insert happen inside the store without suspending, so
            // two taps cannot both pass the duplicate check.
            try await siteProfileRepository.saveIfAbsent(profile)
            siteProfiles.append(profile)
            sortProfiles()
            return true
        } catch {
            lastError = error
            return false
        }
    }

    /// Runs real theme detection for a user-entered URL.
    public func detectTheme(for url: String) async -> ThemeDetectionResult? {
        lastError = nil
        lastDetection = nil

        guard let detector = themeDetector else {
            lastError = SiteProfileError.themeNotInstalled("Theme detection is unavailable")
            return nil
        }

        guard SiteURL.normalizedURL(from: url) != nil else {
            lastError = SiteProfileError.invalidURL(url)
            return nil
        }

        isDetecting = true
        defer { isDetecting = false }

        do {
            let result = try await detector.detectTheme(for: url)
            if !availableThemes.contains(where: { $0.id == result.theme.id }) {
                availableThemes.append(result.theme)
            }
            selectedThemeID = result.theme.id
            lastDetection = result
            return result
        } catch {
            lastError = error
            return nil
        }
    }

    public func deleteProfile(_ profile: SiteProfile) async {
        do {
            try await deleteContent(for: profile)
            try await siteProfileRepository.delete(profile)
            siteProfiles.removeAll { $0.id == profile.id }
        } catch {
            lastError = error
        }
    }

    public func deleteProfiles(at indexSet: IndexSet) async {
        let profiles = indexSet.compactMap { index in
            index < siteProfiles.count ? siteProfiles[index] : nil
        }

        do {
            for profile in profiles {
                try await deleteContent(for: profile)
                try await siteProfileRepository.delete(profile)
            }
            let deletedIDs = Set(profiles.map(\.id))
            siteProfiles.removeAll { deletedIDs.contains($0.id) }
        } catch {
            lastError = error
        }
    }

    /// Deletes the library content that belongs to a site profile.
    ///
    /// Without this, removing a site leaves manga, chapters, pages, progress and
    /// bookmarks that no adapter can ever load again.
    private func deleteContent(for profile: SiteProfile) async throws {
        if let host = URL(string: profile.baseURL)?.host {
            ChallengeCookieStore.shared.removeCookies(forHost: host)
        }

        guard let mangaRepository else { return }

        let manga = try await mangaRepository.fetchAll().filter { $0.siteProfileID == profile.id }
        for entry in manga {
            if let chapterRepository {
                let chapters = try await chapterRepository.fetchByMangaId(entry.id)
                for chapter in chapters {
                    try await pageRepository?.deleteAll(for: chapter.id)
                }
            }
            try await readingProgressRepository?.deleteAll(for: entry.id)
            try await bookmarkRepository?.deleteAll(for: entry.id)
            try await mangaRepository.delete(entry)
        }
    }

    public func updateProfile(_ profile: SiteProfile) async {
        do {
            try await siteProfileRepository.save(profile)
            if let index = siteProfiles.firstIndex(where: { $0.id == profile.id }) {
                siteProfiles[index] = profile
            }
            sortProfiles()
        } catch {
            lastError = error
        }
    }

    public func setEnabled(_ isEnabled: Bool, for profile: SiteProfile) async {
        // Start from the stored copy: a snapshot taken before another edit
        // would otherwise write stale fields back to the repository.
        var updated = siteProfiles.first { $0.id == profile.id } ?? profile
        updated.isEnabled = isEnabled
        await updateProfile(updated)
    }

    public func setCookieHandling(_ handling: CookieHandling, for profile: SiteProfile) async {
        var updated = siteProfiles.first { $0.id == profile.id } ?? profile
        updated.cookieHandling = handling
        await updateProfile(updated)

        // Cookies collected during a challenge are not valid for a site that
        // no longer accepts them. Remove them when handling is disabled.
        if handling == .none, let host = URL(string: profile.baseURL)?.host {
            ChallengeCookieStore.shared.removeCookies(forHost: host)
        }
    }

    /// Changes the adapter theme used by an existing site profile.
    ///
    /// Page keys and cached pages are produced by the previous adapter, so they
    /// are invalidated when the theme actually changes.
    public func setTheme(_ themeID: String, for profile: SiteProfile) async {
        lastError = nil
        guard let theme = availableThemes.first(where: { $0.id == themeID }) else {
            lastError = SiteProfileError.themeNotInstalled(themeID)
            return
        }

        // The view can hold a profile snapshot from before an earlier change.
        // Comparing against the stored copy makes switching back to the
        // original theme a real update instead of a silent no-op.
        let current = siteProfiles.first { $0.id == profile.id } ?? profile
        guard theme.id != current.themeID || theme.version != current.themeVersion else {
            return
        }

        var updated = current
        updated.themeID = theme.id
        updated.themeVersion = theme.version
        await updateProfile(updated)

        if lastError == nil {
            await invalidateCachedPages(for: current)
        }
    }

    /// Drops a detection result that referred to a previous URL.
    public func clearDetection() {
        lastDetection = nil
        lastError = nil
    }

    /// Drops pages fetched through the old adapter, which may use other keys.
    private func invalidateCachedPages(for profile: SiteProfile) async {
        guard let mangaRepository, let chapterRepository, let pageRepository else { return }
        do {
            let manga = try await mangaRepository.fetchAll()
                .filter { $0.siteProfileID == profile.id }
            for entry in manga {
                for chapter in try await chapterRepository.fetchByMangaId(entry.id) {
                    try await pageRepository.deleteAll(for: chapter.id)
                    try await chapterRepository.updateDownloadStatus(
                        chapter.id,
                        isDownloaded: false,
                        downloadedPagesCount: 0
                    )
                }
            }
        } catch {
            lastError = error
        }
    }

    public func updateOverrides(
        _ overrides: ThemeSelectorsOverrides,
        for profile: SiteProfile
    ) async {
        var updated = profile
        updated.selectorOverrides = overrides
        await updateProfile(updated)
    }

    private func sortProfiles() {
        siteProfiles.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
