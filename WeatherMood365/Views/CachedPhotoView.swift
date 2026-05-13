import ImageIO
import SwiftUI
import UIKit

struct CachedPhotoView<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    var contentMode: ContentMode = .fill
    var refreshToken = 0
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: cacheKey) {
            await loadImage()
        }
        .onChange(of: cacheKey) { _, _ in
            image = nil
        }
    }

    private var cacheKey: String {
        guard let url else { return "empty" }
        return PhotoImageCache.shared.cacheKey(
            for: url,
            targetSize: targetSize,
            scale: UIScreen.main.scale,
            refreshToken: refreshToken
        )
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            image = nil
            return
        }

        let size = targetSize
        let scale = UIScreen.main.scale
        let token = refreshToken
        let loadedImage = await PhotoImageCache.shared.image(for: url, targetSize: size, scale: scale, refreshToken: token)
        guard cacheKey == PhotoImageCache.shared.cacheKey(for: url, targetSize: size, scale: scale, refreshToken: token) else { return }
        image = loadedImage
    }
}

private actor KeyTracker {
    private var urlKeys: [String: Set<String>] = [:]

    func addKey(_ key: String, for urlPath: String) {
        urlKeys[urlPath, default: []].insert(key)
    }

    func removeKeys(for urlPath: String) -> Set<String> {
        urlKeys.removeValue(forKey: urlPath) ?? []
    }
}

final class PhotoImageCache: @unchecked Sendable {
    static let shared = PhotoImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let keyTracker = KeyTracker()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func cacheKey(for url: URL, targetSize: CGSize, scale: CGFloat, refreshToken: Int = 0) -> String {
        let pixelWidth = Int((targetSize.width * scale).rounded())
        let pixelHeight = Int((targetSize.height * scale).rounded())
        let modifiedAt = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(pixelWidth)x\(pixelHeight)|\(modifiedAt)|\(refreshToken)"
    }

    func image(for url: URL, targetSize: CGSize, scale: CGFloat, refreshToken: Int = 0) async -> UIImage? {
        let key = cacheKey(for: url, targetSize: targetSize, scale: scale, refreshToken: refreshToken) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let maxPixelSize = max(targetSize.width, targetSize.height) * scale
        let image = Self.downsampledImage(at: url, maxPixelSize: maxPixelSize)
            ?? UIImage(contentsOfFile: url.path)

        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: key, cost: cost)
            await keyTracker.addKey(key as String, for: url.path)
        }

        return image
    }

    func removeImages(for url: URL) {
        Task {
            let keys = await keyTracker.removeKeys(for: url.path)
            await MainActor.run {
                for key in keys {
                    cache.removeObject(forKey: key as NSString)
                }
            }
        }
    }

    private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up))
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
