// SPDX-License-Identifier: MPL-2.0

import SwiftData
import SwiftUI

@main
struct BlankGrimoireApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [])
    }
}
