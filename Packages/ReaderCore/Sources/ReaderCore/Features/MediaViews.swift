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
        /// Bumped by the reader to force a fresh request for the same URL.
        var reloadID: Int = 0
        /// Width/height ratio reserved while the image downloads.
        ///
        /// Reader rows must not collapse to the shape's intrinsic height: a
        /// 10pt placeholder inside a lazy stack changes the content height on
        /// every appearance and makes the scroll view jump.
        var reservedAspectRatio: CGFloat? = nil
        /// Reports the decoded pixel size so the reader can remember it.
        var onImageSize: ((CGSize) -> Void)? = nil

        @State private var image: UIImage?
        @State private var isLoading = false
        @State private var displayedURL: String?

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
            .task(id: "\(url ?? "")-\(reloadID)") {
                await load()
            }
        }

        private var placeholder: some View {
            let base = Rectangle()
                .fill(AppColor.surfaceVariant)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColor.primary)
                    } else {
                        Image(systemName: placeholderIcon)
                            .font(.title)
                            .foregroundStyle(AppColor.onSurfaceVariant)
                    }
                }

            return Group {
                if let reservedAspectRatio, reservedAspectRatio > 0 {
                    base.aspectRatio(reservedAspectRatio, contentMode: .fit)
                } else {
                    base
                }
            }
        }

        private func load() async {
            guard let url, let loader else {
                image = nil
                displayedURL = nil
                return
            }

            if displayedURL != url {
                // The view was recycled for another page: never keep the
                // previous image on screen while the new one downloads.
                image = nil
                displayedURL = url
            }

            // Re-entering the lazy stack: render the already decoded page
            // right away instead of collapsing the row back to its
            // placeholder.
            if let cached = DecodedImageCache.shared.image(for: url) {
                image = cached
                reportSize(of: cached)
                return
            }

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
                    DecodedImageCache.shared.insert(uiImage, for: url)
                    reportSize(of: uiImage)
                } else {
                    // Decoding failed. Keep the previous image or placeholder.
                }
            } catch {
                // Image failures are non-fatal: keep the previous image or
                // placeholder. A later reload bumps `reloadID` and retries.
            }
        }

        private func reportSize(of image: UIImage) {
            guard let onImageSize else { return }
            let scale = image.scale
            onImageSize(
                CGSize(width: image.size.width * scale, height: image.size.height * scale)
            )
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

    /// Small site icon, resolved from the site origin.
    ///
    /// Sites rarely agree on where the icon lives, so the usual browser
    /// locations are tried in order and the first one that decodes wins. Only
    /// relative paths are used: no icon service or domain is hardcoded.
    struct SiteFaviconImage: View {
        let baseURL: String
        let loader: (any ImageLoading)?

        private static let paths = [
            "favicon.ico",
            "favicon.png",
            "apple-touch-icon.png",
            "apple-touch-icon-precomposed.png",
        ]

        @State private var image: UIImage?

        var body: some View {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "globe")
                        .font(.body)
                        .foregroundStyle(AppColor.onSurfaceVariant)
                }
            }
            .task(id: baseURL) { await load() }
        }

        private func load() async {
            image = nil
            guard let loader, let origin = Self.origin(of: baseURL) else { return }

            for path in Self.paths {
                let url = origin.appending(path: path).absoluteString
                guard
                    let data = try? await loader.loadImageData(
                        for: url,
                        headers: nil,
                        siteBaseURL: nil
                    )
                else { continue }

                if let decoded = UIImage(data: data) {
                    image = decoded
                    return
                }
            }
        }

        /// Scheme and host of the profile, without its path.
        private static func origin(of baseURL: String) -> URL? {
            guard let url = URL(string: baseURL),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }
            components.path = ""
            components.query = nil
            components.fragment = nil
            return components.url
        }
    }
#endif
