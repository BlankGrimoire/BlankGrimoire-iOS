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

        do {
            if try await siteProfileRepository.fetchByBaseURL(baseURL) != nil {
                throw SiteProfileError.alreadyExists(baseURL)
            }

            let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = SiteProfile(
                name: displayName.isEmpty ? (SiteURL.host(from: baseURL) ?? baseURL) : displayName,
                baseURL: baseURL,
                themeID: themeID
            )
            try await siteProfileRepository.save(profile)
            await loadProfiles()
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
            await loadProfiles()
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
            await loadProfiles()
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
            await loadProfiles()
        } catch {
            lastError = error
        }
    }

    public func setEnabled(_ isEnabled: Bool, for profile: SiteProfile) async {
        var updated = profile
        updated.isEnabled = isEnabled
        await updateProfile(updated)
    }

    public func setCookieHandling(_ handling: CookieHandling, for profile: SiteProfile) async {
        var updated = profile
        updated.cookieHandling = handling
        await updateProfile(updated)
    }

    /// Changes the adapter theme used by an existing site profile.
    public func setTheme(_ themeID: String, for profile: SiteProfile) async {
        var updated = profile
        updated.themeID = themeID
        updated.themeVersion = availableThemes.first(where: { $0.id == themeID })?.version
        await updateProfile(updated)
    }

    public func updateOverrides(
        _ overrides: ThemeSelectorsOverrides,
        for profile: SiteProfile
    ) async {
        var updated = profile
        updated.selectorOverrides = overrides
        await updateProfile(updated)
    }
}
