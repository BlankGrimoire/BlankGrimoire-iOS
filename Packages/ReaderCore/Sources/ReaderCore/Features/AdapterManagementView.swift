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

        private struct RepositoryIssue: Identifiable {
            let repository: TrustedRepository
            let message: String

            var id: String { repository.url }
        }

        private let store: any AdapterStore
        @State private var repositories: [TrustedRepository] = []
        @State private var adapters: [AdapterBundle] = []
        @State private var availableAdapters: [AvailableAdapter] = []
        @State private var repositoryIssues: [RepositoryIssue] = []
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

                if !repositoryIssues.isEmpty {
                    Section("Repository issues") {
                        ForEach(repositoryIssues) { issue in
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                                Text(issue.repository.name)
                                Text(issue.repository.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(issue.message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    Task { await remove(issue.repository) }
                                }
                            }
                        }
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
                        Text("Use a full HTTPS index URL, for example https://example.org/index.json")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            var messages: [String] = []

            do {
                repositories = try await store.listTrustedRepositories()
            } catch {
                repositories = []
                messages.append("Trusted repositories: \(error.localizedDescription)")
            }

            do {
                adapters = try await store.listInstalledAdapters()
            } catch {
                adapters = []
                messages.append("Installed adapters: \(error.localizedDescription)")
            }

            let result = await loadAvailableAdapters(from: repositories)
            availableAdapters = result.adapters
            repositoryIssues = result.issues

            if !messages.isEmpty {
                errorMessage = messages.joined(separator: "\n")
            }
        }

        private func loadAvailableAdapters(from repositories: [TrustedRepository]) async -> (
            adapters: [AvailableAdapter], issues: [RepositoryIssue]
        ) {
            var result: [AvailableAdapter] = []
            var issues: [RepositoryIssue] = []

            for repository in repositories {
                do {
                    let index = try await store.fetchRepositoryIndex(from: repository.url)
                    result.append(
                        contentsOf: index.extensions.map {
                            AvailableAdapter(repositoryURL: repository.url, entry: $0)
                        })
                } catch {
                    issues.append(
                        RepositoryIssue(
                            repository: repository,
                            message: error.localizedDescription
                        ))
                }
            }

            return (result, issues)
        }

        private func fetchRepository() async {
            guard let indexURL = RepositoryURL.normalizedIndexURL(from: repositoryURL) else {
                errorMessage =
                    "Enter a full HTTPS repository index URL, for example https://example.org/index.json"
                return
            }

            isLoading = true
            defer { isLoading = false }
            do {
                let index = try await store.fetchRepositoryIndex(from: indexURL.absoluteString)
                pendingTrust = (index, indexURL.absoluteString)
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
