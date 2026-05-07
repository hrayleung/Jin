import AppKit
import PDFKit
import XCTest
@testable import Jin

final class PDFKitTextExtractorTests: XCTestCase {
    func testExtractTextReturnsTextAndAppliesCharacterLimit() throws {
        let url = try makeTextPDF("Hello PDF Extractor")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            PDFKitTextExtractor.extractText(from: url, maxCharacters: 5),
            "Hello\n\n[Truncated]"
        )
    }

    func testExtractTextReturnsNilForTextlessPDF() throws {
        let url = try makeTextlessPDF()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(PDFKitTextExtractor.extractText(from: url, maxCharacters: 100))
    }

    private func makeTextPDF(_ text: String) throws -> URL {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        view.string = text
        return try writeTemporaryPDF(view.dataWithPDF(inside: view.bounds))
    }

    private func makeTextlessPDF() throws -> URL {
        let image = NSImage(size: NSSize(width: 300, height: 100))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 300, height: 100)).fill()
        image.unlockFocus()

        let document = PDFDocument()
        let page = try XCTUnwrap(PDFPage(image: image))
        document.insert(page, at: 0)
        return try writeTemporaryPDF(try XCTUnwrap(document.dataRepresentation()))
    }

    private func writeTemporaryPDF(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-pdfkit-extractor-\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
