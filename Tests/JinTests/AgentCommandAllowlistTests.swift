import XCTest
@testable import Jin

final class AgentCommandAllowlistTests: XCTestCase {

    // MARK: - Default safe prefixes

    func testDefaultSafePrefixesIncludesCommonReadOnlyCommands() {
        let prefixes = AgentCommandAllowlist.builtinDefaults
        XCTAssertTrue(prefixes.contains("ls"))
        XCTAssertTrue(prefixes.contains("cat"))
        XCTAssertTrue(prefixes.contains("echo"))
        XCTAssertTrue(prefixes.contains("pwd"))
        XCTAssertTrue(prefixes.contains("which"))
        XCTAssertTrue(prefixes.contains("head"))
        XCTAssertTrue(prefixes.contains("tail"))
        XCTAssertTrue(prefixes.contains("wc"))
        XCTAssertTrue(prefixes.contains("find"))
        XCTAssertTrue(prefixes.contains("grep"))
    }

    func testDefaultSafePrefixesIncludesGitCommands() {
        let prefixes = AgentCommandAllowlist.builtinDefaults
        XCTAssertTrue(prefixes.contains("git status"))
        XCTAssertTrue(prefixes.contains("git log"))
        XCTAssertTrue(prefixes.contains("git diff"))
    }

    // MARK: - Allowed commands

    func testAllowedCommand_lsIsAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "ls -la",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertTrue(allowed)
    }

    func testAllowedCommand_gitStatusIsAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "git status",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertTrue(allowed)
    }

    func testAllowedCommand_gitDiffWithArgsIsAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "git diff HEAD~1",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertTrue(allowed)
    }

    // MARK: - Disallowed commands

    func testDisallowedCommand_rmIsNotAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "rm -rf /",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    func testDisallowedCommand_sudoIsNotAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "sudo rm -rf /",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    func testDisallowedCommand_curlIsNotAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "curl https://example.com",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    func testDisallowedCommand_gitPushIsNotAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "git push origin main",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    // MARK: - Pipe handling

    func testPipeFirstCommandChecked() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "ls -la | grep foo",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertTrue(allowed)
    }

    func testPipeWithDisallowedFirstCommand() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "curl https://example.com | grep foo",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    // MARK: - Session prefixes

    func testSessionPrefixesRespected() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "npm test",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: ["npm"]
        )
        XCTAssertTrue(allowed)
    }

    func testSessionPrefixesDoNotAffectDefaultDenied() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "rm -rf /tmp/test",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    func testSessionPrefixesCanAllowPreviouslyDenied() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "rm tempfile.txt",
            allowedPrefixes: [],
            sessionPrefixes: ["rm"]
        )
        XCTAssertTrue(allowed)
    }

    // MARK: - Edge cases

    func testEmptyCommandNotAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    func testWhitespaceOnlyCommandNotAllowed() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "   ",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }

    func testWhitespaceHandling() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "  ls  -la  ",
            allowedPrefixes: AgentCommandAllowlist.builtinDefaults,
            sessionPrefixes: []
        )
        XCTAssertTrue(allowed)
    }

    func testCustomPrefixMatching() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "swift build --configuration release",
            allowedPrefixes: ["swift build", "swift test"],
            sessionPrefixes: []
        )
        XCTAssertTrue(allowed)
    }

    func testCustomPrefixDoesNotPartialMatch() {
        let notAllowed = AgentCommandAllowlist.isCommandAllowed(
            "swiftlint lint",
            allowedPrefixes: ["swift build", "swift test"],
            sessionPrefixes: []
        )
        XCTAssertFalse(notAllowed)
    }

    func testEmptyAllowlistDeniesEverything() {
        let allowed = AgentCommandAllowlist.isCommandAllowed(
            "ls",
            allowedPrefixes: [],
            sessionPrefixes: []
        )
        XCTAssertFalse(allowed)
    }
}
