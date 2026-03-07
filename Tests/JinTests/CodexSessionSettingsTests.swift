import XCTest
@testable import Jin

final class CodexSessionSettingsTests: XCTestCase {
    func testNormalizeCodexProviderSpecificMigratesLegacyWorkingDirectoryAndDropsDeprecatedKeys() {
        var controls = GenerationControls(providerSpecific: [
            "cwd": AnyCodable("  /tmp/project  "),
            "codex_sandbox_mode": AnyCodable("workspace-write"),
            "codex_personality": AnyCodable(" friendly "),
            "codex_approval_policy": AnyCodable("on-request"),
            "codex_sandbox_policy": AnyCodable(["type": "dangerFullAccess"])
        ])

        controls.normalizeCodexProviderSpecific(for: .codexAppServer)

        XCTAssertEqual(controls.codexWorkingDirectory, "/tmp/project")
        XCTAssertEqual(controls.codexSandboxMode, .workspaceWrite)
        XCTAssertEqual(controls.codexPersonality, .friendly)
        XCTAssertNil(controls.providerSpecific["cwd"])
        XCTAssertNil(controls.providerSpecific["codex_sandbox_mode"])
        XCTAssertNil(controls.providerSpecific["codex_approval_policy"])
        XCTAssertNil(controls.providerSpecific["codex_sandbox_policy"])
        XCTAssertEqual(controls.codexActiveOverrideCount, 2)
    }

    func testNormalizeCodexProviderSpecificRemovesKeysForOtherProviders() {
        var controls = GenerationControls(providerSpecific: [
            "codex_cwd": AnyCodable("/tmp/project"),
            "codex_sandbox_mode": AnyCodable("danger-full-access"),
            "codex_personality": AnyCodable("pragmatic")
        ])

        controls.normalizeCodexProviderSpecific(for: .openai)

        XCTAssertTrue(controls.providerSpecific.isEmpty)
        XCTAssertEqual(controls.codexSandboxMode, .workspaceWrite)
        XCTAssertNil(controls.codexWorkingDirectory)
        XCTAssertNil(controls.codexPersonality)
    }

    func testInternalCodexResumeKeysRoundTripWithoutAffectingVisibleOverrides() {
        var controls = GenerationControls()
        controls.codexResumeThreadID = "remote-thread-123"
        controls.codexPendingRollbackTurns = 2

        XCTAssertEqual(controls.codexResumeThreadID, "remote-thread-123")
        XCTAssertEqual(controls.codexPendingRollbackTurns, 2)
        XCTAssertEqual(controls.codexActiveOverrideCount, 0)

        controls.codexPendingRollbackTurns = 0
        controls.codexResumeThreadID = nil

        XCTAssertNil(controls.codexResumeThreadID)
        XCTAssertEqual(controls.codexPendingRollbackTurns, 0)
    }
}
