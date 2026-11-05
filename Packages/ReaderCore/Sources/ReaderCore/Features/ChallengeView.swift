// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI
    import WebKit

    /// A visible browser surface where the user can complete a site challenge.
    public struct ChallengeView: View {
        private let url: URL
        private let allowedHosts: Set<String>
        private let onComplete: () -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var isLoading = true
        @State private var errorMessage: String?

        public init(
            url: URL,
            allowedHosts: Set<String> = [],
            onComplete: @escaping () -> Void = {}
        ) {
            self.url = url
            self.allowedHosts = allowedHosts
            self.onComplete = onComplete
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
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onComplete()
                            dismiss()
                        }
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
            webView.load(URLRequest(url: url))
            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {}

        final class Coordinator: NSObject, WKNavigationDelegate {
            private let parent: ChallengeWebView

            init(parent: ChallengeWebView) {
                self.parent = parent
            }

            func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
                parent.isLoading = true
            }

            func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
                parent.isLoading = false
            }

            func webView(
                _ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
            ) {
                guard
                    let host = navigationAction.request.url?.host?.lowercased(),
                    parent.allowedHosts.isEmpty || parent.allowedHosts.contains(host)
                else {
                    decisionHandler(.cancel)
                    parent.errorMessage = "Navigation outside the approved site was blocked."
                    return
                }
                decisionHandler(.allow)
            }

            func webView(
                _ webView: WKWebView,
                didFailProvisionalNavigation _: WKNavigation!,
                withError error: Error
            ) {
                parent.isLoading = false
                parent.errorMessage = error.localizedDescription
            }
        }
    }
#endif
