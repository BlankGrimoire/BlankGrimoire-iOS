// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI
    import UIKit

    /// Async image backed by an injected `ImageLoading`.
    ///
    /// When the app runs, `ImageLoading` is a `PipelineImageLoader`, so covers
    /// and favicons go through the IOS-7 memory/disk cache. In previews the
    /// loader is `nil` and the placeholder is shown immediately.
    struct CachedAsyncImage: View {
        let url: String?
        let loader: (any ImageLoading)?
        var headers: [String: String]? = nil
        var contentMode: ContentMode = .fill
        var placeholderIcon: String = "book.closed"

        @State private var image: UIImage?
        @State private var isLoading = false

        var body: some View {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            }
            .task(id: url) {
                await load()
            }
        }

        private var placeholder: some View {
            Rectangle()
                .fill(AppColor.surfaceVariant)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: placeholderIcon)
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
                }
        }

        private func load() async {
            image = nil
            guard let url, let loader else { return }

            isLoading = true
            defer { isLoading = false }

            do {
                let data = try await loader.loadImageData(for: url, headers: headers)
                guard !Task.isCancelled else { return }
                image = UIImage(data: data)
            } catch {
                // Image failures are non-fatal: keep the placeholder.
            }
        }
    }

    /// Cover image shared by the library grid and the manga detail header.
    struct MangaCoverImage: View {
        let url: String?
        let loader: (any ImageLoading)?

        var body: some View {
            CachedAsyncImage(url: url, loader: loader, contentMode: .fill)
        }
    }

    /// Small site icon with a globe placeholder.
    struct SiteFaviconImage: View {
        let baseURL: String
        let loader: (any ImageLoading)?

        private var faviconURL: String? {
            URL(string: baseURL)?.appending(path: "favicon.ico").absoluteString
        }

        var body: some View {
            CachedAsyncImage(
                url: faviconURL,
                loader: loader,
                contentMode: .fit,
                placeholderIcon: "globe"
            )
        }
    }
#endif
