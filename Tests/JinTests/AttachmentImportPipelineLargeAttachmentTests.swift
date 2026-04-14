import Foundation
import XCTest
@testable import Jin

final class AttachmentImportPipelineLargeAttachmentTests: PreferencesSandboxedTestCase {
    func testImportInBackgroundAcceptsFileLargerThanLegacyLimit() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("large.wav")
        try Data(repeating: 0, count: 26 * 1024 * 1024).write(to: sourceURL, options: [.atomic])

        let (attachments, errors) = await AttachmentImportPipeline.importInBackground(from: [sourceURL])

        XCTAssertEqual(errors, [])
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.filename, "large.wav")
        XCTAssertEqual(attachments.first?.mimeType.hasPrefix("audio/"), true)

        if let fileURL = attachments.first?.fileURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    func testImportRecordedAudioClipAcceptsDataLargerThanLegacyLimit() async throws {
        let clip = SpeechToTextManager.RecordedClip(
            data: Data(repeating: 1, count: 26 * 1024 * 1024),
            filename: "recording.wav",
            mimeType: "audio/wav"
        )

        let attachment = try await AttachmentImportPipeline.importRecordedAudioClip(clip)

        XCTAssertEqual(attachment.filename, "recording.wav")
        XCTAssertEqual(attachment.mimeType, "audio/wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.fileURL.path))
    }
}
