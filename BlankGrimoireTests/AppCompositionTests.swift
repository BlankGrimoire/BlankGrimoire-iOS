// SPDX-License-Identifier: MPL-2.0

import Testing

@testable import BlankGrimoire

@MainActor
struct AppCompositionTests {
    @Test func compositionRootBuildsWithInMemoryStore() async throws {
        let container = try AppComposition.makeModelContainer(isStoredInMemoryOnly: true)
        let dependencies = try AppComposition.makeDependencies(container: container)

        #expect(try await dependencies.mangaRepository.count() == 0)
        #expect(try await dependencies.siteProfileRepository.fetchAll().isEmpty)
    }
}
