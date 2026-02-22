import XCTest
import Foundation
@testable import Jin

final class GitHubAutoUpdaterTests: XCTestCase {
    func testLocateExtractedAppPrefersExactNameMatch() throws {
        let fixture = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let extracted = fixture.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: extracted.appendingPathComponent("Jin Beta.app", isDirectory: true),
            withIntermediateDirectories: true
        )
        let exact = extracted.appendingPathComponent("Jin.app", isDirectory: true)
        try FileManager.default.createDirectory(at: exact, withIntermediateDirectories: true)

        let selected = try GitHubAutoUpdater.locateExtractedApp(in: extracted, appNameHint: "Jin")
        XCTAssertEqual(selected.standardizedFileURL, exact.standardizedFileURL)
    }

    func testLocateExtractedAppFallsBackToFirstSortedCandidate() throws {
        let fixture = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let extracted = fixture.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let appA = extracted.appendingPathComponent("A.app", isDirectory: true)
        let appB = extracted.appendingPathComponent("B.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appA, withIntermediateDirectories: true)

        let selected = try GitHubAutoUpdater.locateExtractedApp(in: extracted, appNameHint: "Jin")
        XCTAssertEqual(selected.standardizedFileURL, appA.standardizedFileURL)
    }

    func testValidateInstallTargetRejectsNonAppBundlePath() {
        XCTAssertThrowsError(
            try GitHubAutoUpdater.validateInstallTarget(URL(fileURLWithPath: "/tmp/jin-binary"))
        ) { error in
            guard let updateError = error as? GitHubAutoUpdateError,
                  case .unsupportedInstallLocation = updateError else {
                return XCTFail("Expected .unsupportedInstallLocation, got \(error)")
            }
        }
    }

    func testValidateInstallTargetRejectsMissingBundle() {
        let missingBundle = URL(fileURLWithPath: "/tmp/non-existent/Jin.app")

        XCTAssertThrowsError(try GitHubAutoUpdater.validateInstallTarget(missingBundle)) { error in
            guard let updateError = error as? GitHubAutoUpdateError,
                  case .appBundleNotFound = updateError else {
                return XCTFail("Expected .appBundleNotFound, got \(error)")
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
