// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import SwiftData
import SwiftUI

@main
struct BlankGrimoireApp: App {
    private let container: ModelContainer
    private let dependencies: FeaturesDependencies

    @MainActor
    init() {
        do {
            let container = try AppComposition.makeModelContainer()
            self.container = container
            self.dependencies = try AppComposition.makeDependencies(container: container)
        } catch {
            fatalError("Unable to initialize BlankGrimoire: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
        .modelContainer(container)
    }
}
