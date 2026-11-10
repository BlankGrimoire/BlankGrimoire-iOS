// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI
    import WebKit

    /// A visible browser surface where the user can complete a site challenge.
    ///
    /// The browser is never hidden and never automates the challenge: the user
    /// completes it manually. Cookies set during the challenge are copied into
    /// `ChallengeCookieStore` so later bridge requests reuse the same session.
    public struct ChallengeView: View {
        private let url: URL
        private let allowedHosts: Set<String>
        private let onComplete: () -> Void
        private let onCancel: () -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var isLoading = true
        @State private var errorMessage: String?

        /// Creates a verification browser.
        ///
        /// - Parameter allowedHosts: Hosts the main frame may navigate to. The
        ///   list is required: an empty list would turn the view into an
        ///   unrestricted browser, so it is treated as a programming error.
        public init(
            url: URL,
            allowedHosts: Set<String>,
            onComplete: @escaping () -> Void = {},
            onCancel: @escaping () -> Void = {}
        ) {
            precondition(!allowedHosts.isEmpty, "ChallengeView requires at least one allowed host")
            self.url = url
            self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        public var body: some View {
            NavigationStack {
                ChallengeWebView(
                    url: url,
                    allowedHosts: allowedHosts,
                    isLoading: $isLoading,
                    errorMessage: $errorMessage
                )
                .overlay {
                    if isLoading {
                        ProgressView("Loading…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .navigationTitle("Verification")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onComplete()
                            dismiss()
                        }
                        .disabled(isLoading)
                    }
                }
                .alert(
                    "Unable to load verification",
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
        }
    }

    private struct ChallengeWebView: UIViewRepresentable {
        let url: URL
        let allowedHosts: Set<String>
        @Binding var isLoading: Bool
        @Binding var errorMessage: String?

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeUIView(context: Context) -> WKWebView {
            let webView = WKWebView(frame: .zero)
            webView.navigationDelegate = context.coordinator
            context.coordinator.startObservingCookies(of: webView)
            webView.load(URLRequest(url: url))
            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            context.coordinator.parent = self
        }

        static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
            coordinator.stopObservingCookies()
        }

        final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
            var parent: ChallengeWebView
            private weak var cookieStore: WKHTTPCookieStore?

            init(parent: ChallengeWebView) {
                self.parent = parent
            }

            // MARK: Cookie synchronisation

            func startObservingCookies(of webView: WKWebView) {
                let store = webView.configuration.websiteDataStore.httpCookieStore
                cookieStore = store
                store.add(self)
                syncCookies(from: store)
            }

            func stopObservingCookies() {
                cookieStore?.remove(self)
                cookieStore = nil
            }

            func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
                syncCookies(from: cookieStore)
            }

            private func syncCookies(from store: WKHTTPCookieStore) {
                store.getAllCookies { [weak self] cookies in
                    guard let self else { return }
                    let allowed = cookies.filter { cookie in
                        self.parent.isAllowed(host: cookie.domain)
                    }
                    guard !allowed.isEmpty else { return }
                    for cookie in allowed {
                        ChallengeCookieStore.shared.store([cookie], forHost: cookie.domain)
                    }
                }
            }

            // MARK: Navigation policy

            func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
                parent.isLoading = true
            }

            func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
                parent.isLoading = false
            }

            func webView(
                _ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction
            ) async -> WKNavigationActionPolicy {
                let isMainFrame = navigationAction.targetFrame?.isMainFrame == true

                // Sub-frames (challenge widgets, framesets) are left alone: they
                // frequently live on third-party hosts and blocking them would
                // make the verification impossible to complete.
                guard isMainFrame else {
                    return .allow
                }

                guard let url = navigationAction.request.url else {
                    return .cancel
                }

                // `about:blank` and `about:srcdoc` have no host but are safe.
                if url.scheme == "about" {
                    return .allow
                }

                guard url.scheme?.lowercased() == "https", let host = url.host,
                    parent.isAllowed(host: host)
                else {
                    parent.errorMessage = "Navigation outside the approved site was blocked."
                    parent.isLoading = false
                    return .cancel
                }
                return .allow
            }

            func webView(
                _ webView: WKWebView,
                didFailProvisionalNavigation _: WKNavigation!,
                withError error: Error
            ) {
                handle(error)
            }

            func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
                handle(error)
            }

            private func handle(_ error: Error) {
                parent.isLoading = false
                let nsError = error as NSError
                // Cancellations come from our own policy decisions or WebKit
                // interrupting a frame load; they are not user-facing failures.
                if nsError.code == NSURLErrorCancelled
                    || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
                {
                    return
                }
                parent.errorMessage = error.localizedDescription
            }
        }
    }

    extension ChallengeWebView {
        /// Subdomain-aware host check shared by the policy and cookie sync.
        fileprivate func isAllowed(host: String) -> Bool {
            let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !host.isEmpty else { return false }
            return allowedHosts.contains { pattern in
                let pattern = pattern.lowercased()
                return host == pattern || host.hasSuffix("." + pattern)
            }
        }
    }
#endif
