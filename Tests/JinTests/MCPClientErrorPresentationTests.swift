import XCTest
@testable import Jin

final class MCPClientErrorPresentationTests: XCTestCase {
    func testProcessExitSummaryExplainsSIGTERM() {
        XCTAssertEqual(
            MCPErrorPresentation.processExitSummary(status: 15, reason: .uncaughtSignal),
            "The MCP server process was stopped (SIGTERM) before Jin finished talking to it."
        )
        XCTAssertEqual(
            MCPErrorPresentation.processExitSummary(status: 1, reason: .exited),
            "The MCP server process exited (status 1) before Jin finished talking to it."
        )
    }

    func testProcessExitedDescriptionDoesNotDumpCommandLine() throws {
        let diagnostics = LaunchDiagnostics(
            executablePath: "/opt/homebrew/bin/npx",
            args: ["-y", "mcp-remote", "https://api.example.com/mcp", "--header", "Authorization: Bearer as_sk_secretvalue"],
            workingDirectory: "/tmp",
            nodeEnvironment: nil
        )
        let error = MCPClientError.processExited(
            status: 15,
            reason: .uncaughtSignal,
            stderr: "npm error config prefix cannot be changed from project config: /Users/me/.npmrc",
            diagnostics: diagnostics
        )

        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertFalse(description.contains("as_sk_secretvalue"))
        XCTAssertFalse(description.contains("Command:"))
        XCTAssertTrue(description.contains("SIGTERM"))
        XCTAssertTrue(description.contains("Remote HTTP") || description.contains("~/.npmrc"))
    }

    func testDetailedDescriptionRedactsBearerTokenAndKeepsStderr() {
        let diagnostics = LaunchDiagnostics(
            executablePath: "/opt/homebrew/bin/npx",
            args: ["-y", "mcp-remote", "https://api.example.com/mcp", "--header", "Authorization: Bearer as_sk_secretvalue"],
            workingDirectory: "/tmp",
            nodeEnvironment: nil
        )
        let error = MCPClientError.processExited(
            status: 15,
            reason: .uncaughtSignal,
            stderr: "Using custom headers: {\"Authorization\":\"Bearer as_sk_secretvalue\"}",
            diagnostics: diagnostics
        )

        let details = error.detailedDescription
        XCTAssertTrue(details.contains("mcp-remote"))
        XCTAssertTrue(details.contains("stderr:"))
        XCTAssertFalse(details.contains("as_sk_secretvalue"))
        XCTAssertTrue(details.contains("[redacted]"))
    }

    func testDiagnosticRedactionCoversHeaderJSONAndBareKeys() {
        let raw = """
        Command: npx -y mcp-remote --header "Authorization: Bearer as_sk_secretvalue"
        Using custom headers: {"Authorization":"Bearer as_sk_secretvalue"}
        token=as_sk_secretvalue
        """
        let redacted = MCPDiagnosticRedaction.redact(raw)
        XCTAssertFalse(redacted.contains("as_sk_secretvalue"))
        XCTAssertTrue(redacted.contains("[redacted]"))
    }

    func testChatActionErrorFromMessageSplitsSummaryAndDetails() {
        let presentation = ChatActionErrorPresentation.from(
            message: "Short summary.\n\nLonger details about the failure."
        )
        XCTAssertEqual(presentation.summary, "Short summary.")
        XCTAssertEqual(presentation.details, "Longer details about the failure.")
    }

    func testMCPLoadFailureCopyExplainsMessageStillSent() {
        let failure = MCPServerToolLoadFailure(
            serverID: "anysearch",
            serverName: "Anysearch",
            presentation: MCPErrorPresentation(
                title: "MCP server stopped",
                summary: "The MCP server process was stopped (SIGTERM) before Jin finished talking to it.",
                hint: "Switch to Remote HTTP.",
                details: "stderr:\ninitialize"
            )
        )

        let presentation = ChatActionErrorPresentation.mcpLoadFailures([failure], messageStillSent: true)
        XCTAssertEqual(presentation.title, "Couldn't connect to MCP server")
        XCTAssertTrue(presentation.summary.contains("Anysearch"))
        XCTAssertTrue(presentation.summary.contains("still sent"))
        XCTAssertEqual(presentation.hint, "Switch to Remote HTTP.")
        XCTAssertTrue(presentation.details?.contains("initialize") == true)
    }
}

final class MCPRemoteProxyCommandTests: XCTestCase {
    func testParsesNpxProxyWithBearerHeader() throws {
        let parsed = try XCTUnwrap(
            MCPRemoteProxyCommand.parse(
                command: "npx",
                args: [
                    "-y",
                    "mcp-remote",
                    "https://api.anysearch.com/mcp",
                    "--header",
                    "Authorization: Bearer test-token"
                ]
            )
        )

        XCTAssertEqual(parsed.endpoint.absoluteString, "https://api.anysearch.com/mcp")
        XCTAssertEqual(parsed.headers.count, 1)
        XCTAssertEqual(parsed.headers.first?.name, "Authorization")
        XCTAssertEqual(parsed.headers.first?.value, "Bearer test-token")
        XCTAssertTrue(parsed.headers.first?.isSensitive == true)

        let http = parsed.httpTransport
        XCTAssertEqual(http.endpoint.absoluteString, "https://api.anysearch.com/mcp")
        XCTAssertEqual(http.authentication, .bearerToken("test-token"))
    }

    func testParsesPinnedPackageAndSingleCommandLine() throws {
        let parsed = try XCTUnwrap(
            MCPRemoteProxyCommand.parse(
                commandLine: "npx -y mcp-remote@0.1.37 https://mcp.example.com/mcp",
                argsText: ""
            )
        )
        XCTAssertEqual(parsed.endpoint.absoluteString, "https://mcp.example.com/mcp")
        XCTAssertTrue(parsed.headers.isEmpty)
    }

    func testIgnoresNonProxyCommands() {
        XCTAssertNil(
            MCPRemoteProxyCommand.parse(command: "npx", args: ["-y", "firecrawl-mcp"])
        )
    }
}
