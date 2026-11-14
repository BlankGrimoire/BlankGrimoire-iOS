// SPDX-License-Identifier: MPL-2.0

import XCTest

@testable import ReaderCore

final class LocalizationTests: XCTestCase {
    private let key = "site.error.catalogUnavailable"

    func testSiteErrorsHaveItalianTranslations() throws {
        try assertTranslation(
            language: "it",
            expected: "La navigazione dei siti non è disponibile"
        )
    }

    func testSiteErrorsHaveEnglishTranslations() throws {
        try assertTranslation(
            language: "en",
            expected: "Site browsing is unavailable"
        )
    }

    /// Asserts a translation against the compiled `.lproj` bundle when the
    /// toolchain produced one, and against the source catalog otherwise.
    ///
    /// Older SwiftPM toolchains copy `Localizable.xcstrings` as-is instead of
    /// compiling it into strings tables. The catalog remains the source of
    /// truth in both cases, so the test validates it directly when the
    /// compiled lookup is unavailable.
    private func assertTranslation(
        language: String,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if let path = ReaderCoreResources.bundle.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            let message = bundle.localizedString(
                forKey: key,
                value: nil,
                table: "Localizable"
            )
            XCTAssertEqual(message, expected, file: file, line: line)
            return
        }

        let catalog = try loadCatalog(file: file, line: line)
        let strings = try XCTUnwrap(
            catalog["strings"] as? [String: Any],
            "Missing strings table in Localizable.xcstrings",
            file: file,
            line: line
        )
        let entry = try XCTUnwrap(
            strings[key] as? [String: Any],
            "Missing catalog entry for \(key)",
            file: file,
            line: line
        )
        let localizations = try XCTUnwrap(
            entry["localizations"] as? [String: Any],
            "Missing localizations for \(key)",
            file: file,
            line: line
        )
        let localization = try XCTUnwrap(
            localizations[language] as? [String: Any],
            "Missing \(language) translation for \(key)",
            file: file,
            line: line
        )
        let unit = try XCTUnwrap(
            localization["stringUnit"] as? [String: Any],
            "Missing string unit for \(key) (\(language))",
            file: file,
            line: line
        )

        XCTAssertEqual(unit["value"] as? String, expected, file: file, line: line)
    }

    private func loadCatalog(file: StaticString, line: UInt) throws -> [String: Any] {
        let url: URL
        if let bundled = ReaderCoreResources.bundle.url(
            forResource: "Localizable",
            withExtension: "xcstrings"
        ) {
            url = bundled
        } else {
            // Tests/ReaderCoreTests/LocalizationTests.swift -> package root.
            url = URL(fileURLWithPath: "\(#filePath)")
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/ReaderCore/Resources/Localizable.xcstrings")
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(
            object as? [String: Any],
            "Localizable.xcstrings is not a JSON object",
            file: file,
            line: line
        )
    }
}
