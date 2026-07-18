import AppKit
import ImageIO

/// Shared ImageIO thumbnail helpers for draft chips and message media.
///
/// Prefer these over full-resolution `NSImage(data:)` / `NSImage(contentsOf:)`
/// when only a small UI preview is needed — avoids multi-megapixel RAM spikes.
enum ImageThumbnailSupport {
    /// Downsample an on-disk image to at most `maxPixelSize` on the long edge.
    nonisolated static func downsampledImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    /// Downsample in-memory image bytes to at most `maxPixelSize` on the long edge.
    nonisolated static func downsampledImage(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func thumbnailImage(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
