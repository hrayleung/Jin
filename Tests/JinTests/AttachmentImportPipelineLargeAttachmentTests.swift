import AppKit
import Foundation
import XCTest
@testable import Jin

final class AttachmentImportPipelineLargeAttachmentTests: PreferencesSandboxedTestCase {
    private static let legacyPerFileLimit = 25 * 1024 * 1024
    private static let legacyLargeAttachmentSize = 26 * 1024 * 1024

    func testImportInBackgroundAcceptsFileLargerThanLegacyLimit() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("large.wav")
        try Data(repeating: 0, count: Self.legacyLargeAttachmentSize).write(to: sourceURL, options: [.atomic])

        let (attachments, errors) = await AttachmentImportPipeline.importInBackground(from: [sourceURL])

        XCTAssertEqual(errors, [])
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.filename, "large.wav")
        XCTAssertEqual(attachments.first?.mimeType.hasPrefix("audio/"), true)

        let fileURL = try XCTUnwrap(attachments.first?.fileURL)
        try assertStoredFile(at: fileURL, expectedSize: Self.legacyLargeAttachmentSize)
    }

    func testImportRecordedAudioClipAcceptsDataLargerThanLegacyLimit() async throws {
        let clip = SpeechToTextManager.RecordedClip(
            data: Data(repeating: 1, count: Self.legacyLargeAttachmentSize),
            filename: "recording.wav",
            mimeType: "audio/wav"
        )

        let attachment = try await AttachmentImportPipeline.importRecordedAudioClip(clip)

        XCTAssertEqual(attachment.filename, "recording.wav")
        XCTAssertEqual(attachment.mimeType, "audio/wav")
        try assertStoredFile(at: attachment.fileURL, expectedSize: Self.legacyLargeAttachmentSize)
    }

    func testDroppedImagePathAcceptsPNGGeneratedAboveLegacyLimit() async throws {
        let image = try Self.makeLargeNoisyImage()
        let provider = NSItemProvider(object: image)

        let dropResult: ChatDropHandlingSupport.DropResult = await withCheckedContinuation { continuation in
            XCTAssertTrue(
                ChatDropHandlingSupport.processDropProviders([provider]) { result in
                    continuation.resume(returning: result)
                }
            )
        }

        XCTAssertEqual(dropResult.errors, [])
        let temporaryPNGURL = try XCTUnwrap(dropResult.fileURLs.first)
        defer { try? FileManager.default.removeItem(at: temporaryPNGURL) }

        let temporaryPNGSize = try XCTUnwrap(
            try temporaryPNGURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        XCTAssertGreaterThan(temporaryPNGSize, Self.legacyPerFileLimit)

        let (attachments, errors) = await ChatDropHandlingSupport.importAttachments(from: dropResult.fileURLs)

        XCTAssertEqual(errors, [])
        XCTAssertEqual(attachments.count, 1)
        let attachment = try XCTUnwrap(attachments.first)
        XCTAssertEqual(attachment.mimeType, "image/png")
        try assertStoredFile(at: attachment.fileURL, expectedSize: temporaryPNGSize)
    }

    private func assertStoredFile(at fileURL: URL, expectedSize: Int) throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(
            try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            expectedSize
        )
    }

    private static func makeLargeNoisyImage() throws -> NSImage {
        let width = 3_600
        let height = 3_000
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height

        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: bytesPerRow,
                bitsPerPixel: 32
            )
        )
        let bitmapData = try XCTUnwrap(bitmap.bitmapData)

        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        for offset in 0..<byteCount {
            state = state &* 2862933555777941757 &+ 3037000493
            bitmapData[offset] = UInt8(truncatingIfNeeded: state >> 24)
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
}
