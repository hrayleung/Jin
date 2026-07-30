import AppKit
import ImageIO

/// Decodes an image at a bounded pixel size instead of full resolution.
///
/// `NSImage(data:)` / `NSImage(contentsOf:)` materialize the full-resolution
/// bitmap (a 12 MP photo is ~46 MB decoded) even when the view draws it at
/// thumbnail size. `CGImageSourceCreateThumbnailAtIndex` decodes directly to
/// the target size, so peak and resident memory scale with the display size,
/// not the source size. Pick `maxPixelSize` as the largest point size the
/// image is drawn at × the Retina scale factor.
enum ImageDownsampler {
    static func image(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    static func image(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    /// Approximate decoded-bitmap byte count, for use as an `NSCache` cost.
    static func estimatedBitmapCost(of image: NSImage) -> Int {
        max(1, Int(image.size.width * image.size.height * 4))
    }

    private static func thumbnailImage(from source: CGImageSource, maxPixelSize: Int) -> NSImage? {
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
