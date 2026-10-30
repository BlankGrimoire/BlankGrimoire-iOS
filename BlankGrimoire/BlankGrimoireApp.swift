// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import SwiftData

@main
struct BlankGrimoireApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [])
    }
}