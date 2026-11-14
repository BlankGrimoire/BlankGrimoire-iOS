// SPDX-License-Identifier: MPL-2.0

import Testing

@testable import BlankGrimoire

struct AppConfigurationTests {
    @Test func acceptsValidHTTPSRepositoryURL() {
        let value = "https://themes.example.org/index.json"
        #expect(AppConfiguration.validatedThemesRepositoryURL(value) == value)
    }

    @Test(arguments: [
        nil,
        "",
        "   ",
        "not a url",
        "ftp://themes.example.org/index.json",
        "https:///index.json",
    ])
    func fallsBackToDefaultForInvalidURL(_ value: String?) {
        #expect(
            AppConfiguration.validatedThemesRepositoryURL(value)
                == AppConfiguration.defaultThemesRepositoryURL
        )
    }

    @Test func trimsWhitespaceAroundValidURL() {
        let value = "  https://themes.example.org/index.json  "
        #expect(
            AppConfiguration.validatedThemesRepositoryURL(value)
                == "https://themes.example.org/index.json"
        )
    }

    @Test func networkPolicyIsScopedToRepositoryHost() {
        let policy = AppConfiguration.themesRepositoryPolicy(
            for: "https://themes.example.org/repository/index.json"
        )

        #expect(policy.baseURL == "https://themes.example.org")
        #expect(policy.allowedHosts == ["themes.example.org"])
    }

    @Test func networkPolicyFallsBackToDefaultHostForInvalidURL() {
        let policy = AppConfiguration.themesRepositoryPolicy(for: "file:///tmp/index.json")

        #expect(policy.baseURL == "https://blankgrimoire.github.io")
        #expect(policy.allowedHosts == ["blankgrimoire.github.io"])
    }
}
