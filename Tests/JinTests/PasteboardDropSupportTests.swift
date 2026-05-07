import AppKit
import XCTest
@testable import Jin

final class PasteboardDropSupportTests: XCTestCase {
    func testAcceptedDraggedTypesIncludeEditorInputs() {
        let types = Set(PasteboardDropSupport.acceptedDraggedTypes)

        XCTAssertTrue(types.contains(.fileURL))
        XCTAssertTrue(types.contains(.URL))
        XCTAssertTrue(types.contains(.string))
        XCTAssertTrue(types.contains(.png))
        XCTAssertTrue(types.contains(.tiff))
    }

    func testReadFileURLsReadsDirectFileURLsOnly() throws {
        let fileURL = try makeTemporaryFile(named: "note.txt")
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/file.txt"))
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL, remoteURL as NSURL])

        let urls = PasteboardDropSupport.readFileURLs(from: pasteboard)

        XCTAssertEqual(urls.map(\.standardizedFileURL.path), [fileURL.standardizedFileURL.path])
    }

    func testReadFileURLsFromTextRepresentationsDeduplicatesAndIgnoresRemoteURLs() throws {
        let fileURL = try makeTemporaryFile(named: "dropped.pdf")
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString(
            "\(fileURL.path)\nhttps://example.com/remote.pdf\n\(fileURL.absoluteString)",
            forType: .string
        )

        let urls = PasteboardDropSupport.readFileURLsFromURLAndTextRepresentations(from: pasteboard)

        XCTAssertEqual(urls.map(\.standardizedFileURL.path), [fileURL.standardizedFileURL.path])
    }

    func testReadImagesFallsBackToImageDataTypes() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setData(Self.samplePNGData(), forType: .png)

        let images = PasteboardDropSupport.readImages(from: pasteboard)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.size, NSSize(width: 1, height: 1))
    }

    func testDefaultTextDropHandlingAllowsTextAndRemoteURLs() {
        XCTAssertTrue(
            PasteboardDropSupport.shouldUseDefaultTextDropHandling(
                fileURLs: [],
                types: [.string]
            )
        )
        XCTAssertTrue(
            PasteboardDropSupport.shouldUseDefaultTextDropHandling(
                fileURLs: [URL(string: "https://example.com")!],
                types: [.URL]
            )
        )
    }

    func testDefaultTextDropHandlingRejectsFilePromisesImagesAndOpaqueData() {
        XCTAssertFalse(
            PasteboardDropSupport.shouldUseDefaultTextDropHandling(
                fileURLs: [URL(fileURLWithPath: "/tmp/example.txt")],
                types: [.fileURL]
            )
        )
        XCTAssertFalse(
            PasteboardDropSupport.shouldUseDefaultTextDropHandling(
                fileURLs: [],
                types: [NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")]
            )
        )
        XCTAssertFalse(
            PasteboardDropSupport.shouldUseDefaultTextDropHandling(
                fileURLs: [],
                types: [.png]
            )
        )
        XCTAssertFalse(
            PasteboardDropSupport.shouldUseDefaultTextDropHandling(
                fileURLs: [],
                types: [.init("public.data")]
            )
        )
    }

    func testParseTextValuesReturnsUniqueFileURLsAndTextChunks() throws {
        let fileURL = try makeTemporaryFile(named: "drop.txt")
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString(
            "\(fileURL.path)\nhttps://example.com\nhttps://example.com\n\(fileURL.absoluteString)",
            forType: .string
        )

        let result = PasteboardDropSupport.parseTextValues(from: pasteboard)

        XCTAssertEqual(result.fileURLs.map(\.standardizedFileURL.path), [fileURL.standardizedFileURL.path])
        XCTAssertEqual(result.textChunks, ["https://example.com"])
    }

    func testCanAcceptDragUsesExplicitTypesAndUTTypeFamilies() {
        XCTAssertFalse(PasteboardDropSupport.canAcceptDrag(types: []))
        XCTAssertTrue(PasteboardDropSupport.canAcceptDrag(types: [.string]))
        XCTAssertTrue(PasteboardDropSupport.canAcceptDrag(types: [.init("public.jpeg")]))
        XCTAssertTrue(PasteboardDropSupport.canAcceptDrag(types: [.init("public.data")]))
        XCTAssertFalse(PasteboardDropSupport.canAcceptDrag(types: [.init("com.example.private")]))
    }

    private func makeTemporaryFile(named filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent(filename)
        try Data().write(to: url)
        return url
    }

    private static func samplePNGData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
    }
}
