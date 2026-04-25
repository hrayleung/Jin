import XCTest
@testable import Jin

final class StreamEventDiagnosticsTests: XCTestCase {
    func testDiagnosticNameCoversAllStreamEventCases() {
        let events: [(StreamEvent, String)] = [
            (.messageStart(id: "message_1"), "messageStart"),
            (.contentDelta(.text("hello")), "contentDelta"),
            (.thinkingDelta(.thinking(textDelta: "thought", signature: nil)), "thinkingDelta"),
            (.toolCallStart(ToolCall(id: "call_1", name: "tool", arguments: [:])), "toolCallStart"),
            (.toolCallDelta(id: "call_1", argumentsDelta: "{}"), "toolCallDelta"),
            (.toolCallEnd(ToolCall(id: "call_1", name: "tool", arguments: [:])), "toolCallEnd"),
            (
                .searchActivity(SearchActivity(id: "search_1", type: "search", status: .inProgress)),
                "searchActivity"
            ),
            (
                .codeExecutionActivity(CodeExecutionActivity(id: "code_1", status: .inProgress)),
                "codeExecutionActivity"
            ),
            (
                .codexToolActivity(CodexToolActivity(id: "codex_1", toolName: "shell", status: .running)),
                "codexToolActivity"
            ),
            (.codexInteractionRequest(makeCodexInteractionRequest()), "codexInteractionRequest"),
            (.codexThreadState(CodexThreadState(remoteThreadID: "thread_1")), "codexThreadState"),
            (
                .claudeManagedSessionState(ClaudeManagedAgentSessionState(remoteSessionID: "session_1")),
                "claudeManagedSessionState"
            ),
            (
                .claudeManagedCustomToolResults([
                    ClaudeManagedAgentPendingToolResult(
                        eventID: "event_1",
                        toolCallID: "call_1",
                        toolName: "tool",
                        content: "ok",
                        isError: false,
                        sessionThreadID: nil
                    )
                ]),
                "claudeManagedCustomToolResults"
            ),
            (.messageEnd(usage: Usage(inputTokens: 1, outputTokens: 2)), "messageEnd"),
            (.error(.invalidRequest(message: "bad request")), "error"),
        ]

        for (event, expectedName) in events {
            XCTAssertEqual(event.diagnosticName, expectedName)
        }
    }

    private func makeCodexInteractionRequest() -> CodexInteractionRequest {
        CodexInteractionRequest(
            method: "codex/command_approval",
            threadID: nil,
            turnID: nil,
            itemID: nil,
            kind: .commandApproval(
                CodexCommandApprovalRequest(
                    command: "pwd",
                    cwd: nil,
                    reason: nil,
                    actionSummaries: []
                )
            )
        )
    }
}
