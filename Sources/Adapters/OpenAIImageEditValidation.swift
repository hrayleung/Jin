import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Validate actual image bytes before multipart upload; never log image payloads.
enum OpenAIImageEditValidation {
    struct Raster {
        let source: CGImageSource
        let width: Int
        let height: Int
        let isPNG: Bool
        let mimeType: String
        let hasAlpha: Bool
    }

    static func raster(_ data: Data) throws -> Raster {
        guard data.count <= 50 * 1_024 * 1_024 else {
            throw LLMError.invalidRequest(message: "Image edit inputs must be no larger than 50 MB.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.webP.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw LLMError.invalidRequest(message: "Image edits require readable PNG, JPEG or WebP images. SVG and animated GIF outputs cannot be used directly as edit inputs.")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        return Raster(source: source, width: rotated ? height : width, height: rotated ? width : height,
                      isPNG: type == UTType.png.identifier, mimeType: UTType(type)?.preferredMIMEType ?? "image/png",
                      hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false)
    }

    static func validateGuide(_ data: Data, original: Data?, kind: OpenAIImageEditGuidance) throws {
        let guide = try raster(data)
        guard guide.isPNG else {
            throw LLMError.invalidRequest(message: "The last image must be a PNG with transparency for \(kind.rawValue) editing.")
        }
        if let original {
            let base = try raster(original)
            guard base.width == guide.width, base.height == guide.height else {
                throw LLMError.invalidRequest(message: "The \(kind.rawValue) PNG must match the first image's dimensions after orientation.")
            }
            if kind == .mask, !base.isPNG {
                throw LLMError.invalidRequest(message: "For mask edits, use an original PNG and a matching PNG mask.")
            }
        }
        if kind == .markup {
            guard guide.width <= 16_777_216 / guide.height else {
                throw LLMError.invalidRequest(message: "Markup and its original image may contain at most 16,777,216 pixels each.")
            }
        }
        guard guide.hasAlpha else {
            throw LLMError.invalidRequest(message: "The \(kind.rawValue) PNG needs an alpha channel. Export it with transparency.")
        }
        if kind == .markup {
            guard let cgImage = CGImageSourceCreateImageAtIndex(guide.source, 0, nil), hasTransparentPixels(cgImage) else {
                throw LLMError.invalidRequest(message: "Markup must contain transparent pixels. Attach a separate annotation layer, not a flattened copy of the original.")
            }
        }
    }

    private static func hasTransparentPixels(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in stride(from: 3, to: width * height * 4, by: 4) where bytes[index] < 255 { return true }
        return false
    }
}
