import XCTest
@testable import Jin

final class AgentShellExecutorTests: XCTestCase {

    // MARK: - Basic execution

    func testBasicEcho() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "echo hello",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hello"))
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertGreaterThan(result.durationSeconds, 0)
    }

    func testMultilineOutput() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "echo 'line1\nline2\nline3'",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("line1"))
        XCTAssertTrue(result.stdout.contains("line2"))
        XCTAssertTrue(result.stdout.contains("line3"))
    }

    // MARK: - Exit codes

    func testExitCodeCapture() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "exit 42",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertEqual(result.exitCode, 42)
    }

    func testZeroExitCodeForSuccessfulCommand() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "true",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertEqual(result.exitCode, 0)
    }

    func testNonZeroExitCodeForFailingCommand() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "false",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertNotEqual(result.exitCode, 0)
    }

    // MARK: - Stderr capture

    func testStderrCapture() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "echo error >&2",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertTrue(result.stderr.contains("error"))
    }

    func testStdoutAndStderrSeparated() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "echo out && echo err >&2",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertTrue(result.stdout.contains("out"))
        XCTAssertTrue(result.stderr.contains("err"))
    }

    func testEnvironmentMergePreservesManagedPathAndBlocksLoaderOverrides() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "printf '%s\n' \"$PATH\"; printf '%s\n' \"${DYLD_LIBRARY_PATH-unset}\"",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400,
            environment: [
                "PATH": "/custom/bin",
                "DYLD_LIBRARY_PATH": "/tmp/evil"
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let lines = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("/custom/bin"))
        XCTAssertTrue(lines[0].contains("/usr/bin"))
        XCTAssertNotEqual(lines[1], "/tmp/evil")
    }

    // MARK: - Working directory

    func testWorkingDirectory() async throws {
        let tmpDir = NSTemporaryDirectory()
        let result = try await AgentShellExecutor.execute(
            command: "pwd",
            workingDirectory: tmpDir,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertEqual(result.exitCode, 0)
        let actualPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // On macOS, /tmp is a symlink to /private/tmp and pwd may resolve it.
        // Normalize both sides by stripping /private prefix if present.
        let normalize: (String) -> String = { path in
            path.hasPrefix("/private") ? String(path.dropFirst("/private".count)) : path
        }
        XCTAssertEqual(normalize(actualPath), normalize(tmpDir.hasSuffix("/") ? String(tmpDir.dropLast()) : tmpDir))
    }

    // MARK: - Output truncation

    func testOutputTruncation() async throws {
        // Generate output larger than maxOutputBytes
        let maxBytes = 256
        let result = try await AgentShellExecutor.execute(
            command: "python3 -c \"print('x' * 1000)\"",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: maxBytes
        )

        XCTAssertEqual(result.exitCode, 0)
        // The raw 'x' output is 1000+ chars; truncated output should be much shorter
        // and contain the truncation notice
        XCTAssertTrue(result.stdout.contains("[Output truncated:"))
        XCTAssertLessThan(result.stdout.utf8.count, 1000)
    }

    // MARK: - Timeout

    func testTimeout() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "sleep 60",
            workingDirectory: nil,
            timeout: 1,
            maxOutputBytes: 102_400
        )
        // Process should be terminated with non-zero exit code (SIGTERM = 15)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    // MARK: - Duration tracking

    func testDurationTracking() async throws {
        let result = try await AgentShellExecutor.execute(
            command: "sleep 0.1",
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 102_400
        )

        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0.1)
        XCTAssertLessThan(result.durationSeconds, 5.0)
    }
}
