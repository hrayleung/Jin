import Foundation
import XCTest
@testable import Jin

final class RTKRuntimeSupportTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var tempHomeURL: URL!
    private var helperURL: URL!
    private var previousRTKPath: String?
    private var previousRTKHome: String?

    override func setUpWithError() throws {
        try super.setUpWithError()

        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Jin-RTKTests-\(UUID().uuidString)", isDirectory: true)
        tempHomeURL = tempDirectoryURL.appendingPathComponent("home", isDirectory: true)
        helperURL = tempDirectoryURL.appendingPathComponent("rtk", isDirectory: false)

        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
        try writeStubRTKHelper(to: helperURL)

        previousRTKPath = ProcessInfo.processInfo.environment["JIN_RTK_PATH"]
        previousRTKHome = ProcessInfo.processInfo.environment["JIN_RTK_HOME"]
        setenv("JIN_RTK_PATH", helperURL.path, 1)
        setenv("JIN_RTK_HOME", tempHomeURL.path, 1)
    }

    override func tearDownWithError() throws {
        if let previousRTKPath {
            setenv("JIN_RTK_PATH", previousRTKPath, 1)
        } else {
            unsetenv("JIN_RTK_PATH")
        }

        if let previousRTKHome {
            setenv("JIN_RTK_HOME", previousRTKHome, 1)
        } else {
            unsetenv("JIN_RTK_HOME")
        }

        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }

        helperURL = nil
        tempHomeURL = nil
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testConfigManagerWritesManagedTeeSection() throws {
        try RTKConfigManager.ensureManagedConfiguration()

        let configURL = try RTKConfigManager.configurationFileURL()
        let configContents = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertTrue(configContents.contains("[tee]"))
        XCTAssertTrue(configContents.contains("mode = \"always\""))
        XCTAssertTrue(configContents.contains("enabled = true"))
        XCTAssertTrue(configContents.contains("directory = "))
    }

    func testPrepareShellCommandUsesRTKRewrite() async throws {
        let rewritten = try await RTKRuntimeSupport.prepareShellCommand("git status")
        XCTAssertEqual(rewritten, "rtk git status")
    }

    func testPrepareShellCommandRejectsUnsupportedCommand() async {
        do {
            _ = try await RTKRuntimeSupport.prepareShellCommand("unsupported cmd")
            XCTFail("Expected unsupported command to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("RTK cannot rewrite"))
        }
    }

    func testVersionStringUsesHelper() async throws {
        let version = try await RTKRuntimeSupport.versionString()
        XCTAssertEqual(version, "rtk 0.31.0-test")
    }

    func testAgentShellExecuteUsesRTKAndCapturesRawOutputPath() async throws {
        let controls = makeAgentControls()
        let definitions = await AgentToolHub.shared.toolDefinitions(for: controls)
        let result = try await AgentToolHub.shared.executeTool(
            functionName: AgentToolHub.shellExecuteFunctionName,
            arguments: [
                "command": AnyCodable("git status")
            ],
            routes: definitions.routes,
            controls: controls.agentMode ?? AgentModeControls()
        )

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains("rewritten git output"))
        XCTAssertTrue(result.rawOutputPath?.hasSuffix("git.log") == true)
    }

    func testAgentGrepSearchTreatsNoMatchesAsSuccess() async throws {
        let controls = makeAgentControls()
        let definitions = await AgentToolHub.shared.toolDefinitions(for: controls)
        let result = try await AgentToolHub.shared.executeTool(
            functionName: AgentToolHub.grepSearchFunctionName,
            arguments: [
                "pattern": AnyCodable("no-match"),
                "path": AnyCodable(".")
            ],
            routes: definitions.routes,
            controls: controls.agentMode ?? AgentModeControls()
        )

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains("0 matches"))
        XCTAssertTrue(result.rawOutputPath?.hasSuffix("grep-no-match.log") == true)
    }

    func testAgentApprovalSessionStoreRemembersApprovedKeys() async {
        let store = AgentApprovalSessionStore()
        let isApprovedBefore = await store.isApproved(key: "shell:/tmp:git status")
        XCTAssertFalse(isApprovedBefore)
        await store.approve(key: "shell:/tmp:git status")
        let isApprovedAfter = await store.isApproved(key: "shell:/tmp:git status")
        XCTAssertTrue(isApprovedAfter)
    }

    func testAgentApprovalSessionKeyIncludesCommandAndWorkingDirectory() {
        let key = ChatStreamingOrchestrator.agentApprovalSessionKey(
            functionName: AgentToolHub.shellExecuteFunctionName,
            arguments: [
                "command": AnyCodable("git status"),
                "working_directory": AnyCodable("/tmp/repo")
            ],
            controls: AgentModeControls()
        )

        XCTAssertEqual(key, "shell:/tmp/repo:git status")
    }

    // MARK: - Helpers

    private func makeAgentControls() -> GenerationControls {
        var agentMode = AgentModeControls()
        agentMode.enabled = true
        return GenerationControls(agentMode: agentMode)
    }

    private func writeStubRTKHelper(to url: URL) throws {
        let script = """
        #!/bin/zsh
        set -eu

        cmd="${1:-}"
        if [[ $# -gt 0 ]]; then
          shift
        fi

        tee_dir="${RTK_TEE_DIR:-${TMPDIR:-/tmp}/jin-rtk-tests}"
        mkdir -p "$tee_dir"

        case "$cmd" in
          --version)
            echo "rtk 0.31.0-test"
            ;;
          rewrite)
            raw_cmd="${1:-}"
            case "$raw_cmd" in
              "git status")
                echo "rtk git status"
                ;;
              "unsupported cmd")
                exit 1
                ;;
              *)
                echo "$raw_cmd"
                ;;
            esac
            ;;
          git)
            tee_file="$tee_dir/git.log"
            echo "raw git output" > "$tee_file"
            echo "rewritten git output"
            echo "[full output: $tee_file]"
            ;;
          grep)
            pattern="${1:-}"
            tee_file="$tee_dir/grep-${pattern}.log"
            echo "raw grep output" > "$tee_file"
            if [[ "$pattern" == "no-match" ]]; then
              echo "0 matches for '$pattern'"
              echo "[full output: $tee_file]"
              exit 1
            fi
            echo "2 matches in 1F:"
            echo "[full output: $tee_file]"
            ;;
          find)
            tee_file="$tee_dir/find.log"
            echo "raw find output" > "$tee_file"
            echo "1F 1D:"
            echo "./Sources"
            echo "[full output: $tee_file]"
            ;;
          *)
            echo "unsupported rtk subcommand: $cmd" >&2
            exit 1
            ;;
        esac
        """

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
