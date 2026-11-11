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

        private enum PendingRemoval: Identifiable {
            case repository(TrustedRepository)
            case adapter(AdapterBundle)

            var id: String {
                switch self {
                case .repository(let repository):
                    return "repository::\(repository.url)"
                case .adapter(let adapter):
                    return "adapter::\(adapter.id)"
                }
            }

            var title: String {
                switch self {
                case .repository(let repository):
                    return "Remove \(repository.name)?"
                case .adapter(let adapter):
                    return "Remove \(adapter.themeAdapter.name)?"
                }
            }
        }

        private let store: any AdapterStore
        private let siteProfileRepository: (any SiteProfileRepository)?
        @State private var repositories: [TrustedRepository] = []
        @State private var adapters: [AdapterBundle] = []
        @State private var availableAdapters: [AvailableAdapter] = []
        @State private var repositoryIssues: [RepositoryIssue] = []
        @State private var themeUsage: [String: Int] = [:]
        @State private var updates: [(adapter: AdapterBundle, update: ExtensionEntry)] = []
        @State private var repositoryURL = ""
        @State private var pendingTrust: (index: RepositoryIndex, url: String)?
        @State private var pendingRemoval: PendingRemoval?
        @State private var showTrustDialog = false
        @State private var isLoading = false
        @State private var isBusy = false
        @State private var errorMessage: String?
        @State private var sheetError: String?
        @State private var showingAddRepository = false

        public init(
            store: any AdapterStore,
            siteProfileRepository: (any SiteProfileRepository)? = nil
        ) {
            self.store = store
            self.siteProfileRepository = siteProfileRepository
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
                            Text("Key \(repository.keyFingerprint)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                pendingRemoval = .repository(repository)
                            }
                        }
                    }
                    Button("Add repository", systemImage: "plus") {
                        sheetError = nil
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
                                    pendingRemoval = .repository(issue.repository)
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
                                pendingRemoval = .adapter(adapter)
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
                                Text(installationStatus(for: available.entry))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isInstallable(available.entry) {
                                Button("Install") {
                                    Task { await install(available) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isBusy)
                            }
                        }
                    }
                }

                Section {
                    Button("Check for updates", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await checkForUpdates() }
                    }
                    .disabled(isLoading || isBusy)

                    ForEach(updates, id: \.adapter.id) { item in
                        Button("Update \(item.adapter.themeAdapter.name) to \(item.update.version)") {
                            Task { await update(item) }
                        }
                        .disabled(isBusy)
                    }
                } header: {
                    Text("Updates")
                }
            }
            .navigationTitle("Adapters")
            .overlay {
                if isLoading || isBusy {
                    ProgressView()
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingAddRepository, onDismiss: presentTrustDialogIfNeeded) {
                addRepositorySheet
            }
            .confirmationDialog(
                "Trust this repository?",
                isPresented: $showTrustDialog,
                presenting: pendingTrust
            ) { pending in
                Button("Trust \(pending.index.name)") {
                    pendingTrust = nil
                    Task { await trust(pending) }
                }
                Button("Cancel", role: .cancel) {
                    pendingTrust = nil
                }
            } message: { pending in
                Text(
                    """
                    Key fingerprint \(AdapterKeyFingerprint.short(of: pending.index.publicKey)).
                    Only trust repositories whose fingerprint you can verify with the publisher.
                    """
                )
            }
            .confirmationDialog(
                pendingRemoval?.title ?? "Remove?",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                presenting: pendingRemoval
            ) { removal in
                Button("Remove", role: .destructive) {
                    Task { await perform(removal) }
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            } message: { removal in
                Text(removalMessage(for: removal))
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

        private var addRepositorySheet: some View {
            NavigationStack {
                Form {
                    TextField("Repository index URL", text: $repositoryURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Use a full HTTPS index URL, for example https://example.org/index.json")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let sheetError {
                        Text(sheetError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Fetch and review") {
                        Task { await fetchRepository() }
                    }
                    .disabled(isBusy)
                }
                .navigationTitle("Add repository")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddRepository = false }
                    }
                }
            }
        }

        private func presentTrustDialogIfNeeded() {
            if pendingTrust != nil {
                showTrustDialog = true
            }
        }

        private func load() async {
            isLoading = true
            defer { isLoading = false }

            // The three sources are independent: loading them in parallel keeps
            // the screen from waiting on three sequential round trips.
            async let trustedRepositories = loadTrustedRepositories()
            async let installedAdapters = loadInstalledAdapters()
            async let usage = loadThemeUsage()

            let (repositoryResult, adapterResult) = await (trustedRepositories, installedAdapters)
            themeUsage = await usage

            repositories = repositoryResult.value
            adapters = adapterResult.value

            var messages = repositoryResult.messages + adapterResult.messages

            let result = await loadAvailableAdapters(from: repositories)
            availableAdapters = result.adapters
            repositoryIssues = result.issues

            if !messages.isEmpty {
                errorMessage = messages.joined(separator: "\n")
            }
        }

        private func loadTrustedRepositories() async -> (value: [TrustedRepository], messages: [String]) {
            do {
                return (try await store.listTrustedRepositories(), [])
            } catch {
                return ([], ["Trusted repositories: \(error.localizedDescription)"])
            }
        }

        private func loadInstalledAdapters() async -> (value: [AdapterBundle], messages: [String]) {
            do {
                return (try await store.listInstalledAdapters(), [])
            } catch {
                return ([], ["Installed adapters: \(error.localizedDescription)"])
            }
        }

        /// Counts sites per theme so removing an adapter can warn about them.
        private func loadThemeUsage() async -> [String: Int] {
            guard let siteProfileRepository else { return [:] }
            do {
                let profiles = try await siteProfileRepository.fetchAll()
                return profiles.reduce(into: [:]) { counts, profile in
                    counts[profile.themeID, default: 0] += 1
                }
            } catch {
                return [:]
            }
        }

        private struct RepositoryTimeout: LocalizedError {
            var errorDescription: String? {
                "The repository did not answer within \(Int(AdapterManagementView.indexTimeout.components.seconds)) seconds."
            }
        }

        /// Repositories are contacted in parallel and each one is bounded by a
        /// timeout so a single stalled host cannot block the whole list.
        private static let indexTimeout: Duration = .seconds(15)

        private func loadAvailableAdapters(from repositories: [TrustedRepository]) async -> (
            adapters: [AvailableAdapter], issues: [RepositoryIssue]
        ) {
            var issues: [RepositoryIssue] = []
            var candidates: [(repository: TrustedRepository, entry: ExtensionEntry)] = []

            let indexed = await withTaskGroup(
                of: (offset: Int, repository: TrustedRepository, result: Result<RepositoryIndex, Error>).self
            ) { group in
                for (offset, repository) in repositories.enumerated() {
                    group.addTask {
                        (
                            offset,
                            repository,
                            await Self.fetchIndexResult(store: store, repository: repository)
                        )
                    }
                }

                var collected: [(offset: Int, repository: TrustedRepository, result: Result<RepositoryIndex, Error>)] =
                    []
                for await item in group {
                    collected.append(item)
                }
                return collected.sorted { $0.offset < $1.offset }
            }

            for item in indexed {
                switch item.result {
                case .success(let index):
                    candidates.append(contentsOf: index.extensions.map { (item.repository, $0) })
                case .failure(let error):
                    issues.append(
                        RepositoryIssue(
                            repository: item.repository,
                            message: error.localizedDescription
                        ))
                }
            }

            // The highest version per adapter id wins, regardless of repository
            // order, so results do not depend on the order of the trusted list.
            var bestByID: [String: AvailableAdapter] = [:]
            for candidate in candidates {
                let available = AvailableAdapter(
                    repositoryURL: candidate.repository.url,
                    entry: candidate.entry
                )
                if let existing = bestByID[candidate.entry.id],
                    AdapterVersion(candidate.entry.version) <= AdapterVersion(existing.entry.version)
                {
                    continue
                }
                bestByID[candidate.entry.id] = available
            }

            return (
                bestByID.values.sorted {
                    if $0.entry.name != $1.entry.name {
                        return $0.entry.name.localizedStandardCompare($1.entry.name) == .orderedAscending
                    }
                    return $0.entry.id < $1.entry.id
                },
                issues.sorted { $0.repository.url < $1.repository.url }
            )
        }

        private static func fetchIndexResult(
            store: any AdapterStore,
            repository: TrustedRepository
        ) async -> Result<RepositoryIndex, Error> {
            await withTaskGroup(of: Result<RepositoryIndex, Error>.self) { group in
                group.addTask {
                    do {
                        return .success(try await store.fetchRepositoryIndex(from: repository.url))
                    } catch {
                        return .failure(error)
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: Self.indexTimeout)
                    return .failure(RepositoryTimeout())
                }

                let result = await group.next() ?? .failure(RepositoryTimeout())
                // The first result wins: cancel the losing branch so a slow
                // fetch does not keep running after the timeout.
                group.cancelAll()
                return result
            }
        }

        private func installedAdapter(for id: String) -> AdapterBundle? {
            adapters.first { $0.id == id }
        }

        private func isInstallable(_ entry: ExtensionEntry) -> Bool {
            guard let installed = installedAdapter(for: entry.id) else { return true }
            return AdapterVersion(entry.version) > AdapterVersion(installed.version)
        }

        private func installationStatus(for entry: ExtensionEntry) -> String {
            guard let installed = installedAdapter(for: entry.id) else {
                return "Not installed"
            }
            if AdapterVersion(entry.version) > AdapterVersion(installed.version) {
                return "Update available (installed v\(installed.version))"
            }
            if AdapterVersion(entry.version) < AdapterVersion(installed.version) {
                return "Newer version installed (v\(installed.version))"
            }
            return "Installed"
        }

        private func removalMessage(for removal: PendingRemoval) -> String {
            switch removal {
            case .repository(let repository):
                return
                    "Adapters installed from \(repository.name) stay installed but can no longer be updated until the repository is trusted again."
            case .adapter(let adapter):
                let usage = themeUsage[adapter.id] ?? 0
                if usage > 0 {
                    return
                        "\(usage) site\(usage == 1 ? "" : "s") still use this adapter and will stop working until another adapter is selected."
                }
                return "This adapter will be removed from this device."
            }
        }

        private func fetchRepository() async {
            sheetError = nil
            guard let indexURL = RepositoryURL.normalizedIndexURL(from: repositoryURL) else {
                sheetError =
                    "Enter a full HTTPS repository index URL, for example https://example.org/index.json"
                return
            }

            isBusy = true
            defer { isBusy = false }
            do {
                let index = try await store.fetchRepositoryIndex(from: indexURL.absoluteString)
                pendingTrust = (index, indexURL.absoluteString)
                showingAddRepository = false
            } catch {
                sheetError = error.localizedDescription
            }
        }

        private func trust(_ pending: (index: RepositoryIndex, url: String)) async {
            isBusy = true
            defer { isBusy = false }
            do {
                try await store.trustRepository(pending.index, from: pending.url)
                self.pendingTrust = nil
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func perform(_ removal: PendingRemoval) async {
            pendingRemoval = nil
            switch removal {
            case .repository(let repository):
                await remove(repository)
            case .adapter(let adapter):
                await uninstall(adapter)
            }
        }

        private func remove(_ repository: TrustedRepository) async {
            isBusy = true
            defer { isBusy = false }
            do {
                try await store.removeTrust(for: repository.url)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func uninstall(_ adapter: AdapterBundle) async {
            isBusy = true
            defer { isBusy = false }
            do {
                try await store.uninstallAdapter(id: adapter.id)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func install(_ available: AvailableAdapter) async {
            guard isInstallable(available.entry) else { return }
            isBusy = true
            defer { isBusy = false }
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
            isBusy = true
            defer { isBusy = false }
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
