import Foundation
import XCTest
@testable import Jin

final class WhisperKitModelCatalogTests: XCTestCase {
    func testPreferredDownloadQueryUsesRecommendedExactVariantForMatchingPreset() {
        let query = WhisperKitModelCatalog.preferredDownloadQuery(
            for: "large-v3",
            recommendedModelID: "openai_whisper-large-v3-v20240930"
        )

        XCTAssertEqual(query, "openai_whisper-large-v3-v20240930")
    }

    func testPreferredDownloadQueryFallsBackToPresetDefaultWhenRecommendedVariantIsDifferentFamily() {
        let query = WhisperKitModelCatalog.preferredDownloadQuery(
            for: "base",
            recommendedModelID: "openai_whisper-large-v3-v20240930"
        )

        XCTAssertEqual(query, "openai_whisper-base")
    }

    func testDiscoverLocalModelsFindsOnlyValidModelFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try createValidModelFolder(named: "openai_whisper-base", in: root)
        try createValidModelFolder(named: "openai_whisper-small", in: root)
        try createInvalidModelFolder(named: "not-a-model", in: root)

        let models = WhisperKitService.discoverLocalModels(in: root)

        XCTAssertEqual(models.map(\.id), ["openai_whisper-base", "openai_whisper-small"])
        XCTAssertEqual(models.map(\.presetID), ["base", "small"])
    }

    func testLibrarySnapshotPrefersRecommendedExactLocalVariantForPresetSelection() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let largeOld = WhisperKitService.LocalModel(
            id: "openai_whisper-large-v3",
            folderURL: root.appendingPathComponent("openai_whisper-large-v3", isDirectory: true),
            presetID: "large-v3"
        )
        let largeRecommended = WhisperKitService.LocalModel(
            id: "openai_whisper-large-v3-v20240930",
            folderURL: root.appendingPathComponent("openai_whisper-large-v3-v20240930", isDirectory: true),
            presetID: "large-v3"
        )

        let snapshot = WhisperKitService.LibrarySnapshot(
            repositoryRootURL: root,
            localModels: [largeOld, largeRecommended],
            loadedModelID: nil,
            recommendedModelID: "openai_whisper-large-v3-v20240930"
        )

        XCTAssertEqual(snapshot.localModel(matching: "large-v3")?.id, "openai_whisper-large-v3-v20240930")
    }

    private func createValidModelFolder(named name: String, in root: URL) throws {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for component in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func createInvalidModelFolder(named name: String, in root: URL) throws {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("MelSpectrogram.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}
