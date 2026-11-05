// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Settings surface for trusted repositories and installed adapters.
    public struct AdapterManagementView: View {
        private struct AvailableAdapter: Identifiable {
            let repositoryURL: String
            let entry: ExtensionEntry

            var id: String { "\(repositoryURL)::\(entry.id)::\(entry.version)" }
        }

        private let store: any AdapterStore
        @State private var repositories: [TrustedRepository] = []
        @State private var adapters: [AdapterBundle] = []
        @State private var availableAdapters: [AvailableAdapter] = []
        @State private var updates: [(adapter: AdapterBundle, update: ExtensionEntry)] = []
        @State private var repositoryURL = ""
        @State private var pendingTrust: (index: RepositoryIndex, url: String)?
        @State private var isLoading = false
        @State private var errorMessage: String?
        @State private var showingAddRepository = false

        public init(store: any AdapterStore) {
            self.store = store
        }

        public var body: some View {
            List {
                Section("Trusted repositories") {
                    ForEach(repositories, id: \.url) { repository in
                        VStack(alignment: .leading) {
                            Text(repository.name)
                            Text(repository.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task { await remove(repository) }
                            }
                        }
                    }
                    Button("Add repository", systemImage: "plus") {
                        showingAddRepository = true
                    }
                }

                Section("Installed adapters") {
                    if adapters.isEmpty {
                        Text("No adapters installed")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(adapters, id: \.id) { adapter in
                        VStack(alignment: .leading) {
                            Text(adapter.themeAdapter.name)
                            Text("\(adapter.id) · v\(adapter.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("SHA-256 \(adapter.manifest.sha256)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task { await uninstall(adapter) }
                            }
                        }
                    }
                }

                Section("Available adapters") {
                    if availableAdapters.isEmpty {
                        Text("No installable adapters found")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(availableAdapters) { available in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(available.entry.name)
                                Text("\(available.entry.id) · v\(available.entry.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Install") {
                                Task { await install(available) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section {
                    Button("Check for updates", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await checkForUpdates() }
                    }
                    .disabled(isLoading)

                    ForEach(updates, id: \.adapter.id) { item in
                        Button("Update \(item.adapter.themeAdapter.name) to \(item.update.version)") {
                            Task { await update(item) }
                        }
                    }
                } header: {
                    Text("Updates")
                }
            }
            .navigationTitle("Adapters")
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingAddRepository) {
                NavigationStack {
                    Form {
                        TextField("Repository index URL", text: $repositoryURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Fetch and review") {
                            Task {
                                await fetchRepository()
                                if errorMessage == nil {
                                    showingAddRepository = false
                                }
                            }
                        }
                    }
                    .navigationTitle("Add repository")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingAddRepository = false }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Trust this repository?",
                isPresented: Binding(
                    get: { pendingTrust != nil },
                    set: { if !$0 { pendingTrust = nil } }
                ),
                presenting: pendingTrust
            ) { pending in
                Button("Trust \(pending.index.name)") {
                    Task { await trust(pending) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("The repository key \(pending.index.publicKey) will be stored for future verification.")
            }
            .alert(
                "Adapter error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }

        private func load() async {
            isLoading = true
            defer { isLoading = false }
            do {
                repositories = try await store.listTrustedRepositories()
                adapters = try await store.listInstalledAdapters()
                availableAdapters = try await loadAvailableAdapters(from: repositories)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func loadAvailableAdapters(from repositories: [TrustedRepository]) async throws -> [AvailableAdapter] {
            var result: [AvailableAdapter] = []
            for repository in repositories {
                let index = try await store.fetchRepositoryIndex(from: repository.url)
                result.append(
                    contentsOf: index.extensions.map {
                        AvailableAdapter(repositoryURL: repository.url, entry: $0)
                    })
            }
            return result
        }

        private func fetchRepository() async {
            guard
                let url = URL(string: repositoryURL),
                url.scheme?.lowercased() == "https",
                url.host != nil
            else {
                errorMessage = "Enter a valid HTTPS repository URL."
                return
            }

            isLoading = true
            defer { isLoading = false }
            do {
                let index = try await store.fetchRepositoryIndex(from: repositoryURL)
                pendingTrust = (index, repositoryURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func trust(_ pending: (index: RepositoryIndex, url: String)) async {
            do {
                try await store.trustRepository(pending.index, from: pending.url)
                self.pendingTrust = nil
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func remove(_ repository: TrustedRepository) async {
            do {
                try await store.removeTrust(for: repository.url)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func uninstall(_ adapter: AdapterBundle) async {
            do {
                try await store.uninstallAdapter(id: adapter.id)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func install(_ available: AvailableAdapter) async {
            isLoading = true
            defer { isLoading = false }
            do {
                _ = try await store.installAdapter(
                    id: available.entry.id,
                    version: available.entry.version,
                    from: available.repositoryURL
                )
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func checkForUpdates() async {
            isLoading = true
            defer { isLoading = false }
            do {
                updates = try await store.checkForUpdates()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func update(_ item: (adapter: AdapterBundle, update: ExtensionEntry)) async {
            do {
                _ = try await store.updateAdapter(id: item.adapter.id, to: item.update.version)
                await load()
                updates.removeAll { $0.adapter.id == item.adapter.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
#endif
