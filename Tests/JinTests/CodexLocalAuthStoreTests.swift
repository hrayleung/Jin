import XCTest
@testable import Jin

final class CodexLocalAuthStoreTests: XCTestCase {
    func testAuthFileURLPrefersCodexHomeEnvironment() {
        let url = CodexLocalAuthStore.authFileURL(environment: [
            "CODEX_HOME": " \n /tmp/custom-codex-home \t ",
            "HOME": "/tmp/ignored-home"
        ])

        XCTAssertEqual(url.path, "/tmp/custom-codex-home/auth.json")
    }

    func testAuthFileURLFallsBackToTrimmedHomeWhenCodexHomeIsBlank() {
        let url = CodexLocalAuthStore.authFileURL(environment: [
            "CODEX_HOME": " \n\t ",
            "HOME": " /tmp/codex-home "
        ])

        XCTAssertEqual(url.path, "/tmp/codex-home/.codex/auth.json")
    }

    func testLoadAPIKeyReadsOpenAIAPIKeyFromAuthFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let authURL = tempDirectory.appendingPathComponent("auth.json", isDirectory: false)
        let payload = ["OPENAI_API_KEY": "  sk-test-local-codex-key  "]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: authURL)

        let loaded = CodexLocalAuthStore.loadAPIKey(environment: [
            "CODEX_HOME": tempDirectory.path
        ])

        XCTAssertEqual(loaded, "sk-test-local-codex-key")
    }

    func testLoadAPIKeyReturnsNilWhenAuthFileMissing() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let loaded = CodexLocalAuthStore.loadAPIKey(environment: [
            "CODEX_HOME": tempDirectory.path
        ])

        XCTAssertNil(loaded)
    }

    func testExtractAPIKeySkipsBlankValuesAndTrimsFallbackCandidate() {
        let key = CodexLocalAuthStore.extractAPIKey(from: [
            "OPENAI_API_KEY": " \n\t ",
            "api_key": " \n sk-fallback \t "
        ])

        XCTAssertEqual(key, "sk-fallback")
    }
}
