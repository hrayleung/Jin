import AppKit

enum SVGImagePreviewSupport {
    static func image(data: Data, maxPixelSize: Int) -> NSImage? {
        do { try OpenAIImageSVGValidation.validate(data) } catch { return nil }
        // ImageIO recognizes SVG but its thumbnail API does not render it.
        // AppKit retains the native vector representation at a bounded display size.
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, CGFloat(maxPixelSize) / max(image.size.width, image.size.height))
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return image
    }
}
