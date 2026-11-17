// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import UIKit

    /// Process-wide cache of decoded reader images.
    ///
    /// The network pipeline caches encoded bytes, so a row that leaves a lazy
    /// stack and comes back would decode the same page again and show the
    /// placeholder in the meantime. Keeping the decoded `UIImage` lets those
    /// rows render synchronously, which stops the page height from collapsing
    /// while the reader scrolls back up.
    @MainActor
    final class DecodedImageCache {
        static let shared = DecodedImageCache()

        private let cache = NSCache<NSString, UIImage>()

        private init() {
            // NSCache purges itself under memory pressure, which is what a
            // decoded-image cache wants: pages can always be decoded again
            // from the encoded bytes in `ImagePipeline`.
            cache.countLimit = 48
            cache.totalCostLimit = 128 * 1024 * 1024
        }

        func image(for url: String) -> UIImage? {
            cache.object(forKey: url as NSString)
        }

        func insert(_ image: UIImage, for url: String) {
            let scale = image.scale
            let cost = Int(image.size.width * scale * image.size.height * scale * 4)
            cache.setObject(image, forKey: url as NSString, cost: cost)
        }

        func removeAll() {
            cache.removeAllObjects()
        }

        func removeImages(for urls: [String]) {
            for url in urls {
                cache.removeObject(forKey: url as NSString)
            }
        }
    }
#endif
