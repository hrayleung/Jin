import AppKit
import ImageIO
import UniformTypeIdentifiers

enum AnimatedImagePreviewSupport {
    /// Bound the decoded frames retained by NSImage. Original GIF bytes are
    /// stored separately and are always used for opening, copying and exporting.
    static func image(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1, count <= 64 else {
            return ImageDownsampler.image(data: data, maxPixelSize: maxPixelSize)
        }
        let edge = min(maxPixelSize, max(1, Int(sqrt(Double(32 * 1_024 * 1_024 / (count * 4))))))
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.gif.identifier as CFString, count, nil) else { return nil }
        if let properties = CGImageSourceCopyProperties(source, nil) {
            CGImageDestinationSetProperties(destination, properties)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: false
        ]
        for index in 0..<count {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            CGImageDestinationAddImage(destination, frame, properties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return NSImage(data: output as Data)
    }
}
