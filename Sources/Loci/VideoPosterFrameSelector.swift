import AppKit
import AVFoundation
import CoreGraphics

enum VideoPosterFrameSelector {
    private static let extensions: Set<String> = [
        "mov", "mp4", "m4v", "webm", "avi", "mkv", "mpeg", "mpg"
    ]

    static func supports(fileExtension: String) -> Bool {
        extensions.contains(fileExtension.lowercased())
    }

    static func pngData(for url: URL, maxPixelSize: Int) async -> Data? {
        await Task.detached(priority: .utility) {
            autoreleasepool {
                let asset = AVURLAsset(url: url)
                let duration = asset.duration.seconds
                let usableDuration = duration.isFinite && duration > 0 ? duration : 3
                let sampleSeconds = [0.08, 0.22, 0.42, 0.64]
                    .map { min(max(usableDuration * $0, 0.05), max(usableDuration - 0.05, 0.05)) }

                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

                var bestImage: CGImage?
                var bestScore = -Double.infinity
                for seconds in sampleSeconds {
                    let time = CMTime(seconds: seconds, preferredTimescale: 600)
                    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
                    let score = visualScore(for: image)
                    if score > bestScore {
                        bestScore = score
                        bestImage = image
                    }
                }

                guard let bestImage else { return nil }
                let bitmap = NSBitmapImageRep(cgImage: bestImage)
                return bitmap.representation(using: .png, properties: [:])
            }
        }.value
    }

    /// Favors frames with usable exposure and visual information, rejecting
    /// the black title/fade frames common at the start of videos.
    private static func visualScore(for image: CGImage) -> Double {
        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let values = pixels.map { Double($0) / 255 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let exposure = max(0, 1 - abs(mean - 0.52) / 0.52)
        return variance * 2.4 + exposure * 0.22
    }
}
