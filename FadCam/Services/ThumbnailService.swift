import AVFoundation
import UIKit

class ThumbnailService {
    static let shared = ThumbnailService()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 100
    }

    func thumbnail(for url: URL, size: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        let nsurl = url as NSURL
        if let cached = cache.object(forKey: nsurl) {
            return cached
        }

        // Handle image files directly
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                cache.setObject(image, forKey: nsurl)
                return image
            }
            return nil
        }

        // Handle video files with AVAssetImageGenerator
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size

        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 1, preferredTimescale: 600))]) { _, cgImage, _, result, error in
                if result == .succeeded, let cgImage = cgImage {
                    let image = UIImage(cgImage: cgImage)
                    self.cache.setObject(image, forKey: nsurl)
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func invalidateCache(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
