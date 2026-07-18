import AppKit
import XCTest
@testable import Jin

final class ImageThumbnailSupportTests: XCTestCase {
    func testDownsamplesPNGDataBelowMaxPixelSize() throws {
        // 400×300 solid red PNG
        let sourceImage = NSImage(size: NSSize(width: 400, height: 300))
        sourceImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 300).fill()
        sourceImage.unlockFocus()

        guard let tiff = sourceImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode test PNG")
            return
        }

        let thumb = ImageThumbnailSupport.downsampledImage(data: png, maxPixelSize: 96)
        XCTAssertNotNil(thumb)
        guard let cgImage = thumb?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Expected CGImage from thumbnail")
            return
        }
        XCTAssertLessThanOrEqual(max(cgImage.width, cgImage.height), 96)
        XCTAssertGreaterThan(cgImage.width, 0)
        XCTAssertGreaterThan(cgImage.height, 0)
    }

    func testDownsamplesFileURL() throws {
        let sourceImage = NSImage(size: NSSize(width: 512, height: 512))
        sourceImage.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 512, height: 512).fill()
        sourceImage.unlockFocus()

        guard let tiff = sourceImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode test PNG")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-thumb-test-\(UUID().uuidString).png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumb = ImageThumbnailSupport.downsampledImage(at: url, maxPixelSize: 64)
        XCTAssertNotNil(thumb)
        guard let cgImage = thumb?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Expected CGImage from file thumbnail")
            return
        }
        XCTAssertLessThanOrEqual(max(cgImage.width, cgImage.height), 64)
    }
}
