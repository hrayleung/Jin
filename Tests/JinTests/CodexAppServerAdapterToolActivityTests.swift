import XCTest
@testable import Jin

final class CodexAppServerAdapterToolActivityTests: XCTestCase {

    // MARK: - codexToolActivityFromDynamicToolCall

    func testCodexToolActivityParsesShellCommand() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-shell-1",
                "type": "dynamicToolCall",
                "name": "shell",
                "status": "running",
                "arguments": [
                    "command": "ls -la /tmp"
                ]
            ],
            "turnId": "turn-1"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "tool-shell-1")
        XCTAssertEqual(activity.toolName, "shell")
        XCTAssertEqual(activity.status, .running)
        XCTAssertEqual(activity.arguments["command"]?.value as? String, "ls -la /tmp")
    }

    func testCodexToolActivityParsesFileEditTool() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-edit-2",
                "type": "dynamicToolCall",
                "name": "edit_file",
                "arguments": [
                    "path": "/src/main.swift",
                    "content": "print(\"hello\")"
                ]
            ],
            "turnId": "turn-2"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/completed",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "tool-edit-2")
        XCTAssertEqual(activity.toolName, "edit_file")
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.arguments["path"]?.value as? String, "/src/main.swift")
        XCTAssertEqual(activity.arguments["content"]?.value as? String, "print(\"hello\")")
    }

    func testCodexToolActivityParsesGenericTool() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-gen-3",
                "type": "dynamicToolCall",
                "name": "read_file",
                "input": [
                    "file": "/README.md"
                ],
                "output": "# README\nHello world"
            ],
            "turnId": "turn-3"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/completed",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.toolName, "read_file")
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.arguments["file"]?.value as? String, "/README.md")
        XCTAssertEqual(activity.output, "# README\nHello world")
    }

    // MARK: - Web Search Exclusion

    func testCodexToolActivityReturnsNilForWebSearchTool() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-ws-4",
                "type": "dynamicToolCall",
                "name": "web_search",
                "status": "completed",
                "arguments": [
                    "query": "swift news"
                ]
            ],
            "turnId": "turn-4"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
            item: item,
            method: "item/completed",
            params: params,
            fallbackTurnID: nil
        )

        XCTAssertNil(activity, "Web search tools should be excluded from codex tool activities")
    }

    func testCodexToolActivityReturnsNilForBrowserSearchTool() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-ws-5",
                "type": "dynamicToolCall",
                "name": "browser.search",
                "status": "searching"
            ],
            "turnId": "turn-5"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
            item: item,
            method: "item/updated",
            params: params,
            fallbackTurnID: nil
        )

        XCTAssertNil(activity, "Browser search tools should be excluded from codex tool activities")
    }

    func testCodexToolActivityDoesNotTreatResearchToolAsWebSearch() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-rs-6",
                "type": "dynamicToolCall",
                "name": "research_notes",
                "status": "completed"
            ],
            "turnId": "turn-6"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
            item: item,
            method: "item/completed",
            params: params,
            fallbackTurnID: nil
        )

        XCTAssertNotNil(activity, "Non-web search tools should remain in codex tool activities")
        XCTAssertEqual(activity?.toolName, "research_notes")
    }

    // MARK: - Status Derivation

    func testCodexToolActivityStatusFromMethodStarted() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "status-1",
                "type": "dynamicToolCall",
                "name": "run_command"
            ],
            "turnId": "turn-s1"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.status, .running)
    }

    func testCodexToolActivityStatusFromMethodCompleted() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "status-2",
                "type": "dynamicToolCall",
                "name": "run_command"
            ],
            "turnId": "turn-s2"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/completed",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.status, .completed)
    }

    func testCodexToolActivityStatusFromMethodFailed() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "status-3",
                "type": "dynamicToolCall",
                "name": "run_command"
            ],
            "turnId": "turn-s3"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/dynamicToolCall/failed",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.status, .failed)
    }

    // MARK: - Argument Extraction

    func testCodexToolActivityExtractsTopLevelCommandFallback() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "args-1",
                "type": "dynamicToolCall",
                "name": "exec",
                "command": "echo hello"
            ],
            "turnId": "turn-a1"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.arguments["command"]?.value as? String, "echo hello")
    }

    func testCodexToolActivityExtractsFromInputObject() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "args-2",
                "type": "dynamicToolCall",
                "name": "write_file",
                "input": [
                    "path": "/tmp/test.txt",
                    "content": "hello world"
                ]
            ],
            "turnId": "turn-a2"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.arguments["path"]?.value as? String, "/tmp/test.txt")
        XCTAssertEqual(activity.arguments["content"]?.value as? String, "hello world")
    }

    // MARK: - codexToolActivityFromCodexItem

    func testCodexToolActivityFromCodexItemReturnsNilForWebSearchType() throws {
        let payload: [String: Any] = [
            "id": "ws-item-1",
            "type": "webSearch",
            "query": "swift news"
        ]
        let item = try TestJSONHelpers.makeJSONObject(payload)

        let activity = CodexAppServerAdapter.codexToolActivityFromCodexItem(
            item: item,
            method: "item/started",
            params: item,
            fallbackTurnID: nil
        )

        XCTAssertNil(activity, "webSearch items should return nil")
    }

    func testCodexToolActivityFromCodexItemDispatchesDynamicToolCall() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "dispatch-1",
                "type": "dynamicToolCall",
                "name": "list_dir",
                "arguments": [
                    "path": "/src"
                ]
            ],
            "turnId": "turn-d1"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromCodexItem(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.toolName, "list_dir")
        XCTAssertEqual(activity.status, .running)
    }

    // MARK: - commandExecution Items

    func testCodexToolActivityParsesCommandExecution() throws {
        let payload: [String: Any] = [
            "id": "cmd-exec-1",
            "type": "commandExecution",
            "command": "ls -la /tmp",
            "cwd": "/Users/test/project",
            "status": "inProgress"
        ]

        let item = try TestJSONHelpers.makeJSONObject(payload)
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromCodexItem(
                item: item,
                method: "item/started",
                params: item,
                fallbackTurnID: "turn-cmd1"
            )
        )

        XCTAssertEqual(activity.id, "cmd-exec-1")
        XCTAssertEqual(activity.toolName, "ls")
        XCTAssertEqual(activity.status, .running)
        XCTAssertEqual(activity.arguments["command"]?.value as? String, "ls -la /tmp")
        XCTAssertEqual(activity.arguments["cwd"]?.value as? String, "/Users/test/project")
    }

    func testCodexToolActivityParsesCompletedCommandExecution() throws {
        let payload: [String: Any] = [
            "id": "cmd-exec-2",
            "type": "commandExecution",
            "command": "cat README.md",
            "status": "completed",
            "exitCode": 0,
            "aggregatedOutput": "# Hello World"
        ]

        let item = try TestJSONHelpers.makeJSONObject(payload)
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromCodexItem(
                item: item,
                method: "item/completed",
                params: item,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.output, "# Hello World")
        // exitCode comes through as Int from item.int(at:)
        XCTAssertNotNil(activity.arguments["exitCode"])
    }

    // MARK: - fileChange Items

    func testCodexToolActivityParsesFileChange() throws {
        let payload: [String: Any] = [
            "id": "fc-1",
            "type": "fileChange",
            "changes": [
                [
                    "path": "/src/main.swift",
                    "kind": "edit",
                    "diff": "@@ -1 +1 @@\n-old\n+new"
                ]
            ],
            "status": "inProgress"
        ]

        let item = try TestJSONHelpers.makeJSONObject(payload)
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromCodexItem(
                item: item,
                method: "item/started",
                params: item,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "fc-1")
        XCTAssertEqual(activity.toolName, "edit: main.swift")
        XCTAssertEqual(activity.status, .running)
        if let paths = activity.arguments["paths"]?.value as? [String] {
            XCTAssertEqual(paths, ["/src/main.swift"])
        } else {
            XCTFail("Expected paths argument")
        }
    }

    // MARK: - mcpToolCall Items

    func testCodexToolActivityParsesMcpToolCall() throws {
        let payload: [String: Any] = [
            "id": "mcp-1",
            "type": "mcpToolCall",
            "server": "filesystem",
            "tool": "read_file",
            "status": "inProgress",
            "arguments": [
                "path": "/etc/hosts"
            ]
        ]

        let item = try TestJSONHelpers.makeJSONObject(payload)
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromCodexItem(
                item: item,
                method: "item/started",
                params: item,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.toolName, "filesystem/read_file")
        XCTAssertEqual(activity.status, .running)
        XCTAssertEqual(activity.arguments["path"]?.value as? String, "/etc/hosts")
    }

    // MARK: - Non-tool Items

    func testCodexToolActivityReturnsNilForAgentMessage() throws {
        let payload: [String: Any] = [
            "id": "msg-1",
            "type": "agentMessage",
            "message": ["content": [["type": "output_text", "text": "Hello"]]]
        ]

        let item = try TestJSONHelpers.makeJSONObject(payload)
        let activity = CodexAppServerAdapter.codexToolActivityFromCodexItem(
            item: item,
            method: "item/started",
            params: item,
            fallbackTurnID: nil
        )

        XCTAssertNil(activity, "agentMessage items should return nil")
    }

    func testCodexToolActivityReturnsNilForReasoningItem() throws {
        let payload: [String: Any] = [
            "id": "reason-1",
            "type": "reasoning"
        ]

        let item = try TestJSONHelpers.makeJSONObject(payload)
        let activity = CodexAppServerAdapter.codexToolActivityFromCodexItem(
            item: item,
            method: "item/started",
            params: item,
            fallbackTurnID: nil
        )

        XCTAssertNil(activity, "reasoning items should return nil")
    }

    // MARK: - merged(with:)

    func testMergedUpdatesStatusAndPreservesEarlierFields() {
        let original = CodexToolActivity(
            id: "merge-1",
            toolName: "shell",
            status: .running,
            arguments: ["command": AnyCodable("ls")]
        )

        let update = CodexToolActivity(
            id: "merge-1",
            toolName: "",
            status: .completed,
            arguments: [:],
            output: "file1.txt\nfile2.txt"
        )

        let merged = original.merged(with: update)

        XCTAssertEqual(merged.id, "merge-1")
        XCTAssertEqual(merged.toolName, "shell", "Empty toolName in update should preserve original")
        XCTAssertEqual(merged.status, .completed)
        XCTAssertEqual(merged.arguments["command"]?.value as? String, "ls")
        XCTAssertEqual(merged.output, "file1.txt\nfile2.txt")
    }

    func testMergedOverwritesToolNameWhenPresent() {
        let original = CodexToolActivity(
            id: "merge-2",
            toolName: "exec",
            status: .running,
            arguments: [:]
        )

        let update = CodexToolActivity(
            id: "merge-2",
            toolName: "shell",
            status: .completed,
            arguments: [:]
        )

        let merged = original.merged(with: update)
        XCTAssertEqual(merged.toolName, "shell")
    }

    // MARK: - ID Generation

    func testCodexToolActivityUsesExplicitID() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "explicit-id-123",
                "type": "dynamicToolCall",
                "name": "run_command"
            ],
            "turnId": "turn-id1"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "explicit-id-123")
    }

    func testCodexToolActivityGeneratesFallbackIDFromTurnAndToolName() throws {
        let payload: [String: Any] = [
            "item": [
                "type": "dynamicToolCall",
                "name": "RunCommand"
            ],
            "turnId": "turn-42"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "codex_tool_turn-42_runcommand")
    }

    func testCodexToolActivityGeneratesFallbackIDWithSequenceSuffixWhenAvailable() throws {
        let payload: [String: Any] = [
            "item": [
                "type": "dynamicToolCall",
                "name": "RunCommand",
                "sequenceNumber": 7
            ],
            "turnId": "turn-42"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.codexToolActivityFromDynamicToolCall(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "codex_tool_turn-42_runcommand_seq7")
    }
}
