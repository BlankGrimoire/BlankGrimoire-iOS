// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

final class LocalizationTests: XCTestCase {
    func testSiteErrorsHaveItalianTranslations() throws {
        // `String(localized:)` follows the process language, so the test opens
        // the Italian resource bundle directly.
        let path = try XCTUnwrap(ReaderCoreResources.bundle.path(forResource: "it", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let message = bundle.localizedString(
            forKey: "site.error.catalogUnavailable",
            value: nil,
            table: "Localizable"
        )

        XCTAssertEqual(message, "La navigazione dei siti non è disponibile")
    }

    func testSiteErrorsHaveEnglishTranslations() throws {
        let path = try XCTUnwrap(ReaderCoreResources.bundle.path(forResource: "en", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let message = bundle.localizedString(
            forKey: "site.error.catalogUnavailable",
            value: nil,
            table: "Localizable"
        )

        XCTAssertEqual(message, "Site browsing is unavailable")
    }
}
