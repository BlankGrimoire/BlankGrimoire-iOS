// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "book.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                
                Text("BlankGrimoire")
                    .font(.largeTitle.weight(.bold))
                
                Text("Theme-based reader for iOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button("Adapter Store") {
                        // TODO: Navigate to adapter store
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Settings") {
                        // TODO: Navigate to settings
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.bottom, 40)
            }
            .padding()
            .navigationTitle("BlankGrimoire")
        }
    }
}

#Preview {
    ContentView()
}