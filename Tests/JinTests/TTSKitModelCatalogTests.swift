import Foundation
import XCTest
@testable import Jin

final class TTSKitModelCatalogTests: XCTestCase {
    func testNormalizedModelIDConvertsLegacyStoredValue() {
        XCTAssertEqual(TTSKitModelCatalog.normalizedModelID("qwen3-tts-0.6b"), "0.6b")
        XCTAssertEqual(TTSKitModelCatalog.normalizedModelID(" qwen3-tts-1.7b "), "1.7b")
    }

    func testResolvedPlaybackModeDefaultsToAuto() {
        XCTAssertEqual(TTSKitPlaybackMode.resolved(nil), .auto)
        XCTAssertEqual(TTSKitPlaybackMode.resolved("invalid"), .auto)
        XCTAssertEqual(TTSKitPlaybackMode.resolved("generate_first"), .generateFirst)
    }

    func testDiscoverLocalModelsFindsInstalledVariants() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try createInstalledVariant(modelID: "0.6b", in: root)
        try createInstalledVariant(modelID: "1.7b", in: root)

        let models = TTSKitService.discoverLocalModels(in: root)

        XCTAssertEqual(models.map(\.id), ["0.6b", "1.7b"])
        XCTAssertEqual(models.map(\.versionDirectory), ["12hz-0.6b-customvoice", "12hz-1.7b-customvoice"])
    }

    private func createInstalledVariant(modelID: String, in root: URL) throws {
        guard let preset = TTSKitModelCatalog.preset(for: modelID) else {
            XCTFail("Missing preset for \(modelID)")
            return
        }

        let components: [(String, String)] = [
            ("text_projector", "W8A16"),
            ("code_embedder", "W16A16"),
            ("multi_code_embedder", "W16A16"),
            ("code_decoder", "W8A16-stateful"),
            ("multi_code_decoder", "W8A16"),
            ("speech_decoder", "W8A16")
        ]

        for (component, variant) in components {
            let modelBundle = root
                .appendingPathComponent("qwen3_tts", isDirectory: true)
                .appendingPathComponent(component, isDirectory: true)
                .appendingPathComponent(preset.versionDirectory, isDirectory: true)
                .appendingPathComponent(variant, isDirectory: true)
                .appendingPathComponent("Dummy.mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: modelBundle, withIntermediateDirectories: true)
        }
    }
}
