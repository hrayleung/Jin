import XCTest
@testable import Jin

final class CodexProviderIntegrationTests: XCTestCase {
    func testCodexProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.codexAppServer.displayName, "Codex App Server (Beta)")
        XCTAssertEqual(ProviderType.codexAppServer.defaultBaseURL, "ws://127.0.0.1:4500")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .codexAppServer), "OpenAI")
    }

    func testProviderManagerCreatesCodexAdapter() async throws {
        let config = ProviderConfig(
            id: "codex-provider",
            name: "Codex App Server",
            type: .codexAppServer,
            apiKey: "test-key",
            baseURL: ProviderType.codexAppServer.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is CodexAppServerAdapter)
    }

    func testProviderManagerAllowsCodexWithoutAPIKey() async throws {
        let config = ProviderConfig(
            id: "codex-provider-no-key",
            name: "Codex App Server",
            type: .codexAppServer,
            apiKey: nil,
            baseURL: ProviderType.codexAppServer.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is CodexAppServerAdapter)
    }

    func testProviderManagerUsesLocalCodexAuthWhenModeSelected() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let authURL = tempDirectory.appendingPathComponent("auth.json", isDirectory: false)
        let payload = ["OPENAI_API_KEY": "sk-local-mode-test"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: authURL)

        let previousCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_HOME", tempDirectory.path, 1)
        defer {
            if let previousCodexHome {
                setenv("CODEX_HOME", previousCodexHome, 1)
            } else {
                unsetenv("CODEX_HOME")
            }
        }

        let config = ProviderConfig(
            id: "codex-provider-local-auth",
            name: "Codex App Server",
            type: .codexAppServer,
            authModeHint: CodexLocalAuthStore.authModeHint,
            apiKey: nil,
            baseURL: ProviderType.codexAppServer.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is CodexAppServerAdapter)
    }

    func testProviderManagerThrowsWhenLocalCodexAuthSelectedButNoKey() async {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previousCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_HOME", tempDirectory.path, 1)
        defer {
            if let previousCodexHome {
                setenv("CODEX_HOME", previousCodexHome, 1)
            } else {
                unsetenv("CODEX_HOME")
            }
        }

        let config = ProviderConfig(
            id: "codex-provider-local-auth-missing",
            name: "Codex App Server",
            type: .codexAppServer,
            authModeHint: CodexLocalAuthStore.authModeHint,
            apiKey: nil,
            baseURL: ProviderType.codexAppServer.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()

        do {
            _ = try await manager.createAdapter(for: config)
            XCTFail("Expected missing API key error for local auth mode without auth.json")
        } catch {
            guard case ProviderError.missingAPIKey = error else {
                XCTFail("Expected ProviderError.missingAPIKey, got \(error)")
                return
            }
        }
    }
}
