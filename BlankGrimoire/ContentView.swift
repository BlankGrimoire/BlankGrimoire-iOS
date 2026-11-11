// SPDX-License-Identifier: MPL-2.0

import ReaderCore
import SwiftUI

struct ContentView: View {
    let dependencies: FeaturesDependencies

    var body: some View {
        Features.makeTabView(dependencies: dependencies)
    }
}

#if DEBUG
    #Preview {
        ContentView(dependencies: .preview)
    }
#endif
