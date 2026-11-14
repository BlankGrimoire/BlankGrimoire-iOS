// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI
    import UIKit
    import ImageIO
    import MobileCoreServices

    /// Async image backed by an injected `ImageLoading`.
    ///
    /// When the app runs, `ImageLoading` is a `PipelineImageLoader`, so covers
    /// and favicons go through the IOS-7 memory/disk cache. In previews the
    /// loader is `nil` and the placeholder is shown immediately.
    struct CachedAsyncImage: View {
        let url: String?
        let loader: (any ImageLoading)?
        var headers: [String: String]? = nil
        /// Origin of the site that produced the image. Used to recover from a
        /// CDN `Referer` rejection without hardcoding CDN domains.
        var siteBaseURL: String? = nil
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
                let data = try await loader.loadImageData(
                    for: url,
                    headers: headers,
                    siteBaseURL: siteBaseURL
                )
                guard !Task.isCancelled else { return }
                // Use ImageIO for robust WebP decoding (supports more variants than UIImage(data:))
                if let uiImage = decodeImage(data: data) {
                    image = uiImage
                } else {
                    // Decoding failed. Keep placeholder.
                }
            } catch {
                // Image failures are non-fatal: keep the placeholder.
            }
        }

        private func decodeImage(data: Data) -> UIImage? {
            // Try UIImage first (fast path for common formats)
            if let img = UIImage(data: data) {
                return img
            }
            // Fallback to ImageIO for WebP and other formats
            // Try with options to force decoding
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldAllowFloat: true,
                kCGImageSourceTypeIdentifierHint: "public.webp" as CFString,
            ]
            if let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
            {
                return UIImage(cgImage: cgImage)
            }
            // Try without options as fallback
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            {
                return UIImage(cgImage: cgImage)
            }
            // Try with PNG hint (some servers serve PNG for .webp URLs)
            let pngOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceTypeIdentifierHint: "public.png" as CFString,
            ]
            if let source = CGImageSourceCreateWithData(data as CFData, pngOptions as CFDictionary),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, pngOptions as CFDictionary)
            {
                return UIImage(cgImage: cgImage)
            }
            // Try with JPEG hint
            let jpegOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceTypeIdentifierHint: "public.jpeg" as CFString,
            ]
            if let source = CGImageSourceCreateWithData(data as CFData, jpegOptions as CFDictionary),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, jpegOptions as CFDictionary)
            {
                return UIImage(cgImage: cgImage)
            }
            // Last resort: try to create from raw bitmap if it's a simple format
            return nil
        }
    }

    /// Cover image shared by the library grid and the manga detail header.
    struct MangaCoverImage: View {
        let url: String?
        let loader: (any ImageLoading)?
        var siteBaseURL: String? = nil

        var body: some View {
            CachedAsyncImage(
                url: url,
                loader: loader,
                siteBaseURL: siteBaseURL,
                contentMode: .fill
            )
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
