// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import XCTest

final class SiteProfileTests: XCTestCase {

    func testSiteProfileCreation() {
        let profile = SiteProfile(
            name: "Example Library",
            baseURL: "https://example.org",
            themeID: "theme.example",
            themeVersion: "1.0.0"
        )

        XCTAssertEqual(profile.name, "Example Library")
        XCTAssertEqual(profile.baseURL, "https://example.org")
        XCTAssertEqual(profile.themeID, "theme.example")
        XCTAssertEqual(profile.themeVersion, "1.0.0")
        XCTAssertTrue(profile.isEnabled)
        XCTAssertNil(profile.lastAccessedAt)
    }

    func testSiteProfileWithCustomOverrides() {
        let overrides = ThemeSelectorsOverrides(
            search: .init(
                path: "/custom-search", item: ".custom-item", title: ".custom-title", link: "a", cover: "img",
                nextPage: ".next"),
            details: .init(
                title: "h1.custom", cover: ".custom-cover img", synopsis: ".custom-synopsis",
                authors: ".custom-authors", artists: ".custom-artists", altTitles: ".custom-alt", tags: ".custom-tags",
                status: ".custom-status", contentRating: ".custom-rating"),
            chapters: .init(item: ".custom-chapter", link: "a", title: ".custom-title", date: ".custom-date"),
            pages: .init(strategies: [.css(.init(image: ".custom-reader img", srcAttributes: ["data-src"]))]),
            attribution: .init(logo: ".custom-logo img", credits: ".custom-credits")
        )

        let profile = SiteProfile(
            name: "Custom Site",
            baseURL: "https://custom.org",
            themeID: "theme.custom",
            selectorOverrides: overrides
        )

        XCTAssertEqual(profile.selectorOverrides.search?.path, "/custom-search")
        XCTAssertEqual(profile.selectorOverrides.details?.title, "h1.custom")
    }

    func testSiteProfileMakeSiteContext() {
        let profile = SiteProfile(
            name: "Test Site",
            baseURL: "https://test.org",
            themeID: "theme.test"
        )

        let context = profile.makeSiteContext()

        XCTAssertEqual(context.baseURL, "https://test.org")
        XCTAssertEqual(context.siteName, "Test Site")
    }

    func testSiteProfileMakeNetworkPolicy() {
        let profile = SiteProfile(
            name: "Policy Site",
            baseURL: "https://policy.org",
            themeID: "theme.policy",
            customHeaders: ["User-Agent": "CustomAgent"],
            cookieHandling: .none,
            maxRedirects: 3,
            timeout: 15
        )

        let policy = profile.makeNetworkPolicy()

        XCTAssertEqual(policy.baseURL, "https://policy.org")
        XCTAssertEqual(policy.allowedHosts, ["policy.org"])
        XCTAssertEqual(policy.cookieHandling, .none)
        XCTAssertEqual(policy.maxRedirects, 3)
        XCTAssertEqual(policy.timeout, 15)
        XCTAssertEqual(policy.defaultHeaders["User-Agent"], "CustomAgent")
    }

    func testSiteProfileTouched() {
        let profile = SiteProfile(
            name: "Touch Site",
            baseURL: "https://touch.org",
            themeID: "theme.touch"
        )

        let touched = profile.touched()

        XCTAssertNotNil(touched.lastAccessedAt)
        XCTAssertEqual(touched.id, profile.id)
        XCTAssertEqual(touched.name, profile.name)
    }

    func testSiteProfileEquality() {
        let profile1 = SiteProfile(name: "Site", baseURL: "https://site.org", themeID: "theme.id")
        let profile2 = SiteProfile(id: profile1.id, name: "Site", baseURL: "https://site.org", themeID: "theme.id")
        let profile3 = SiteProfile(name: "Other", baseURL: "https://other.org", themeID: "theme.id")

        XCTAssertEqual(profile1, profile2)
        XCTAssertNotEqual(profile1, profile3)
    }
}
