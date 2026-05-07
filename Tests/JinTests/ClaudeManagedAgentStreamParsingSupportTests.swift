import XCTest
@testable import Jin

final class ClaudeManagedAgentStreamParsingSupportTests: XCTestCase {
    func testParseMessageAndIdleEmitsTextCitationsUsageAndSessionState() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_initial")

        _ = try parse(
            #"{"type":"span.model_request_end","model_usage":{"input_tokens":2,"output_tokens":3,"cache_read_input_tokens":5,"cache_creation_input_tokens":7}}"#,
            state: &state
        )
        _ = try parse(
            #"{"type":"span.model_request_end","model_usage":{"input_tokens":11,"output_tokens":13,"cache_read_input_tokens":17,"cache_creation_input_tokens":19}}"#,
            state: &state
        )

        let messageResult = try parse(
            #"{"type":"agent.message","id":"msg_1","session_id":"sess_updated","model":{"id":"claude-sonnet-4-6"},"content":[{"type":"text","text":"Done","citations":[{"url":"https://example.com/result","title":"Result","cited_text":"Relevant quote"}]}]}"#,
            state: &state
        )
        let idleResult = try parse(
            #"{"type":"session.status_idle","model_id":"claude-sonnet-4-6","stop_reason":{"type":"end_turn"}}"#,
            state: &state
        )
        let events = messageResult.events + idleResult.events

        XCTAssertEqual(state.sessionID, "sess_updated")
        XCTAssertTrue(state.didEmitMessageEnd)
        XCTAssertContainsSessionState(events, sessionID: "sess_updated", modelID: "claude-sonnet-4-6")
        XCTAssertContainsMessageStart(events, id: "msg_1")
        XCTAssertContainsTextDelta(events, text: "Done")

        let citationActivity = try XCTUnwrap(searchActivities(in: events).last)
        XCTAssertEqual(citationActivity.id, "msg_1:sources")
        XCTAssertEqual(citationActivity.status, .completed)
        XCTAssertEqual(citationActivity.arguments["url"]?.value as? String, "https://example.com/result")
        XCTAssertEqual(citationActivity.arguments["title"]?.value as? String, "Result")

        let usage = try XCTUnwrap(messageEndUsage(in: events))
        XCTAssertEqual(usage.inputTokens, 13)
        XCTAssertEqual(usage.outputTokens, 16)
        XCTAssertEqual(usage.cachedTokens, 22)
        XCTAssertEqual(usage.cacheCreationTokens, 26)
    }

    func testParseUsageUsesNestedSpanModelUsageFallback() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        _ = try parse(
            #"{"type":"span.model_request_end","span":{"model_usage":{"input_tokens":4,"output_tokens":6,"thinking_tokens":8,"cache_read_input_tokens":10,"cache_creation_input_tokens":12}}}"#,
            state: &state
        )
        let messageResult = try parse(
            #"{"type":"agent.message","id":"msg_nested_usage","text":"Done"}"#,
            state: &state
        )
        let idleResult = try parse(
            #"{"type":"session.status_idle","stop_reason":{"type":"end_turn"}}"#,
            state: &state
        )
        let events = messageResult.events + idleResult.events

        let usage = try XCTUnwrap(messageEndUsage(in: events))
        XCTAssertEqual(usage.inputTokens, 4)
        XCTAssertEqual(usage.outputTokens, 6)
        XCTAssertEqual(usage.thinkingTokens, 8)
        XCTAssertEqual(usage.cachedTokens, 10)
        XCTAssertEqual(usage.cacheCreationTokens, 12)
    }

    func testParseEventIgnoresNonObjectJSONLines() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(#"["session.status_running"]"#, state: &state)

        XCTAssertTrue(result.events.isEmpty)
        XCTAssertNil(result.pendingInteraction)
    }

    func testParseEventPropagatesMalformedJSONErrors() {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        XCTAssertThrowsError(try parse(#"{"type":"agent.message""#, state: &state))
    }

    func testParseMessageSearchSourcesDeduplicateAndPreserveFirstMetadata() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"type":"agent.message","id":"msg_sources","content":[{"type":"text","text":"Done","citations":[{"url":"https://example.com/page","title":"First title","snippet":"First snippet"},{"url":"https://EXAMPLE.com/page","title":"Second title","snippet":"Second snippet"},{"source":{"url":"https://swift.org","name":"Swift"},"text":"Swift source"}]}]}"#,
            state: &state
        )

        let activity = try XCTUnwrap(searchActivities(in: result.events).last)
        let sources = try XCTUnwrap(activity.arguments["sources"]?.value as? [[String: Any]])
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.first?["url"] as? String, "https://example.com/page")
        XCTAssertEqual(sources.first?["title"] as? String, "First title")
        XCTAssertEqual(sources.first?["snippet"] as? String, "First snippet")
        XCTAssertEqual(sources.last?["url"] as? String, "https://swift.org")
        XCTAssertEqual(sources.last?["title"] as? String, "Swift")
    }

    func testParseMessageSearchSourcesFallbackToURLsInText() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"type":"agent.message","id":"msg_url_text","text":"Read https://example.com/docs, then https://EXAMPLE.com/docs and https://swift.org)."}"#,
            state: &state
        )

        let activity = try XCTUnwrap(searchActivities(in: result.events).last)
        let sources = try XCTUnwrap(activity.arguments["sources"]?.value as? [[String: Any]])
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.first?["url"] as? String, "https://example.com/docs")
        XCTAssertEqual(sources.last?["url"] as? String, "https://swift.org")
    }

    func testParseMessageSearchSourcesAcceptSourceStringURL() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"type":"agent.message","id":"msg_source_string","content":[{"type":"text","text":"Done","citations":[{"source":" https://example.com/source-string ","name":"Source name","summary":"Source summary"}]}]}"#,
            state: &state
        )

        let activity = try XCTUnwrap(searchActivities(in: result.events).last)
        let sources = try XCTUnwrap(activity.arguments["sources"]?.value as? [[String: Any]])
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?["url"] as? String, "https://example.com/source-string")
        XCTAssertEqual(sources.first?["title"] as? String, "Source name")
        XCTAssertEqual(sources.first?["snippet"] as? String, "Source summary")
    }

    func testParseMessagePrefersContentTextPartsOverFallbackTextFields() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"type":"agent.message","id":"msg_content_precedence","content":[{"type":"image","url":"https://example.com/image.png"},{"type":"text","text":"First content part"},{"type":"text","text":"Second content part"}],"delta":{"text":"Delta fallback"},"text":"Top-level fallback"}"#,
            state: &state
        )

        let textDeltas = textDeltas(in: result.events)
        XCTAssertEqual(textDeltas, ["First content part", "Second content part"])
    }

    func testParseToolActivitiesAndCustomToolCall() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")
        let tools = [
            ToolDefinition(
                id: "lookup",
                name: "lookup",
                description: "Lookup",
                parameters: ParameterSchema(properties: [:]),
                source: .builtin
            )
        ]

        let searchStart = try parse(
            #"{"type":"agent.tool_use","id":"search_1","name":"web_search","input":{"query":"swift"},"evaluated_permission":"allow"}"#,
            state: &state,
            tools: tools
        )
        let searchEnd = try parse(
            #"{"type":"agent.tool_result","tool_use_id":"search_1","is_error":false,"content":[{"type":"web_search_result","source":{"url":"https://swift.org","title":"Swift"},"snippet":"Swift site"}]}"#,
            state: &state,
            tools: tools
        )
        let toolStart = try parse(
            #"{"type":"agent.mcp_tool_use","id":"tool_1","name":"shell","input":{"cmd":"pwd"},"evaluated_permission":"allow"}"#,
            state: &state,
            tools: tools
        )
        let toolEnd = try parse(
            #"{"type":"agent.mcp_tool_result","mcp_tool_use_id":"tool_1","is_error":false,"content":[{"type":"text","text":"/tmp/project"}]}"#,
            state: &state,
            tools: tools
        )
        let customTool = try parse(
            #"{"type":"agent.custom_tool_use","id":"custom_1","name":"lookup","input":{"query":"Jin"},"session_thread_id":"thread_1","custom_tool_use_id":"underlying_1"}"#,
            state: &state,
            tools: tools
        )
        let events = searchStart.events + searchEnd.events + toolStart.events + toolEnd.events + customTool.events

        let searchEvents = searchActivities(in: events)
        XCTAssertEqual(searchEvents.count, 2)
        XCTAssertEqual(searchEvents.first?.status, .inProgress)
        XCTAssertEqual(searchEvents.last?.status, .completed)
        XCTAssertEqual(searchEvents.first?.arguments["query"]?.value as? String, "swift")
        XCTAssertEqual(searchEvents.last?.arguments["url"]?.value as? String, "https://swift.org")

        let toolEvents = codexToolActivities(in: events)
        XCTAssertEqual(toolEvents.count, 2)
        XCTAssertEqual(toolEvents.first?.status, .running)
        XCTAssertEqual(toolEvents.first?.arguments["cmd"]?.value as? String, "pwd")
        XCTAssertEqual(toolEvents.last?.status, .completed)
        XCTAssertEqual(toolEvents.last?.output, "/tmp/project")

        let startedToolCall = try XCTUnwrap(toolCallStarts(in: events).first)
        XCTAssertEqual(startedToolCall.id, "custom_1")
        XCTAssertEqual(startedToolCall.name, "lookup")
        XCTAssertEqual(startedToolCall.arguments["query"]?.value as? String, "Jin")
        XCTAssertEqual(startedToolCall.providerContextValue(for: "session_thread_id"), "thread_1")
        XCTAssertEqual(startedToolCall.providerContextValue(for: "underlying_tool_use_id"), "underlying_1")
        XCTAssertEqual(toolCallEnds(in: events).first?.id, "custom_1")
    }

    func testParseToolUseAcceptsToolNameAndArgumentsFallbacks() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"type":"agent.tool_use","id":"tool_named","tool_name":"shell","arguments":{"cmd":"ls"},"evaluated_permission":"allow"}"#,
            state: &state
        )

        let activity = try XCTUnwrap(codexToolActivities(in: result.events).first)
        XCTAssertEqual(activity.id, "tool_named")
        XCTAssertEqual(activity.toolName, "shell")
        XCTAssertEqual(activity.arguments["cmd"]?.value as? String, "ls")
    }

    func testParseToolUseWithoutPermissionIsRecordedAsAllowed() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let searchResult = try parse(
            #"{"type":"agent.tool_use","id":"search_without_permission","name":"web_search","input":{"query":"swift"}}"#,
            state: &state
        )
        let toolResult = try parse(
            #"{"type":"agent.mcp_tool_use","id":"tool_without_permission","name":"shell","input":{"cmd":"pwd"}}"#,
            state: &state
        )

        XCTAssertEqual(searchActivities(in: searchResult.events).first?.status, .inProgress)
        XCTAssertEqual(codexToolActivities(in: toolResult.events).first?.status, .running)
        XCTAssertTrue(state.pendingApprovalInteractions.isEmpty)
    }

    func testParseFailedToolResultsUseFailedStatuses() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let searchStart = try parse(
            #"{"type":"agent.tool_use","id":"search_failed","name":"web_search","input":{"query":"swift"},"evaluated_permission":"allow"}"#,
            state: &state
        )
        let searchEnd = try parse(
            #"{"type":"agent.tool_result","tool_use_id":"search_failed","is_error":true,"content":[{"source":{"url":"https://swift.org","title":"Swift"}}]}"#,
            state: &state
        )
        let toolStart = try parse(
            #"{"type":"agent.mcp_tool_use","id":"tool_failed","name":"shell","input":{"cmd":"rm tmp"},"evaluated_permission":"allow"}"#,
            state: &state
        )
        let toolEnd = try parse(
            #"{"type":"agent.mcp_tool_result","mcp_tool_use_id":"tool_failed","is_error":true,"content":[{"type":"text","text":"permission denied"}]}"#,
            state: &state
        )
        let events = searchStart.events + searchEnd.events + toolStart.events + toolEnd.events

        XCTAssertEqual(searchActivities(in: events).last?.status, .failed)

        let failedTool = try XCTUnwrap(codexToolActivities(in: events).last)
        XCTAssertEqual(failedTool.status, .failed)
        XCTAssertEqual(failedTool.output, "permission denied")
    }

    func testParseGenericToolResultJoinsTrimmedTextAndURLContentChunks() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        _ = try parse(
            #"{"type":"agent.mcp_tool_use","id":"tool_chunks","name":"fetch","input":{"url":"https://example.com"},"evaluated_permission":"allow"}"#,
            state: &state
        )
        let result = try parse(
            #"{"type":"agent.mcp_tool_result","mcp_tool_use_id":"tool_chunks","is_error":false,"content":[{"type":"text","text":"  first line  "},{"type":"link","url":" https://example.com/result "},{"type":"text","text":"\n\n"}],"text":"top-level fallback"}"#,
            state: &state
        )

        let activity = try XCTUnwrap(codexToolActivities(in: result.events).last)
        XCTAssertEqual(activity.output, "first line\nhttps://example.com/result")
    }

    func testParseToolResultsUseProviderSpecificReferencedIDs() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        _ = try parse(
            #"{"type":"agent.tool_use","id":"search_provider_id","name":"web_search","input":{"query":"swift"},"evaluated_permission":"allow"}"#,
            state: &state
        )
        _ = try parse(
            #"{"type":"agent.mcp_tool_use","id":"mcp_provider_id","name":"shell","input":{"cmd":"pwd"},"evaluated_permission":"allow"}"#,
            state: &state
        )

        let searchResult = try parse(
            #"{"type":"agent.tool_result","tool_use_id":"search_provider_id","is_error":false,"content":[{"source":{"url":"https://swift.org","title":"Swift"}}]}"#,
            state: &state
        )
        let mcpResult = try parse(
            #"{"type":"agent.mcp_tool_result","mcp_tool_use_id":"mcp_provider_id","is_error":false,"content":[{"type":"text","text":"/repo"}]}"#,
            state: &state
        )

        XCTAssertEqual(searchActivities(in: searchResult.events).last?.id, "search_provider_id")
        XCTAssertEqual(codexToolActivities(in: mcpResult.events).last?.id, "mcp_provider_id")
    }

    func testParseToolUseFallsBackToProviderSpecificIDsForResultCorrelation() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let searchStart = try parse(
            #"{"type":"agent.tool_use","tool_use_id":"search_fallback_id","name":"web_search","input":{"query":"swift"},"evaluated_permission":"allow"}"#,
            state: &state
        )
        let mcpStart = try parse(
            #"{"type":"agent.mcp_tool_use","mcp_tool_use_id":"mcp_fallback_id","name":"shell","input":{"cmd":"pwd"},"evaluated_permission":"allow"}"#,
            state: &state
        )
        let searchEnd = try parse(
            #"{"type":"agent.tool_result","tool_use_id":"search_fallback_id","is_error":false,"content":[{"source":{"url":"https://swift.org","title":"Swift"}}]}"#,
            state: &state
        )
        let mcpEnd = try parse(
            #"{"type":"agent.mcp_tool_result","mcp_tool_use_id":"mcp_fallback_id","is_error":false,"content":[{"type":"text","text":"/repo"}]}"#,
            state: &state
        )

        XCTAssertEqual(searchActivities(in: searchStart.events).first?.id, "search_fallback_id")
        XCTAssertEqual(codexToolActivities(in: mcpStart.events).first?.id, "mcp_fallback_id")
        XCTAssertEqual(searchActivities(in: searchEnd.events).last?.status, .completed)
        XCTAssertEqual(codexToolActivities(in: mcpEnd.events).last?.output, "/repo")
    }

    func testParseToolResultsWithoutReferencedIDLeavePendingActivitiesUntouched() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        _ = try parse(
            #"{"type":"agent.tool_use","id":"search_pending","name":"web_search","input":{"query":"swift"},"evaluated_permission":"allow"}"#,
            state: &state
        )
        _ = try parse(
            #"{"type":"agent.mcp_tool_use","id":"mcp_pending","name":"shell","input":{"cmd":"pwd"},"evaluated_permission":"allow"}"#,
            state: &state
        )

        let searchResult = try parse(
            #"{"type":"agent.tool_result","is_error":false,"content":[{"source":{"url":"https://swift.org","title":"Swift"}}]}"#,
            state: &state
        )
        let mcpResult = try parse(
            #"{"type":"agent.mcp_tool_result","is_error":false,"content":[{"type":"text","text":"/repo"}]}"#,
            state: &state
        )

        XCTAssertTrue(searchResult.events.isEmpty)
        XCTAssertTrue(mcpResult.events.isEmpty)
        XCTAssertEqual(state.pendingSearchActivities.keys.sorted(), ["search_pending"])
        XCTAssertEqual(state.pendingGenericToolActivities.keys.sorted(), ["mcp_pending"])
    }

    func testParseCustomToolCallFallsBackToToolUseIDAndArgumentsObject() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")
        let tools = [
            ToolDefinition(
                id: "lookup",
                name: "lookup",
                description: "Lookup",
                parameters: ParameterSchema(properties: [:]),
                source: .builtin
            )
        ]

        let result = try parse(
            #"{"type":"agent.custom_tool_use","tool_use_id":"underlying_fallback","tool_name":"lookup","arguments":{"query":"fallback"},"session_thread_id":"thread_fallback"}"#,
            state: &state,
            tools: tools
        )

        let startedToolCall = try XCTUnwrap(toolCallStarts(in: result.events).first)
        XCTAssertEqual(startedToolCall.id, "underlying_fallback")
        XCTAssertEqual(startedToolCall.name, "lookup")
        XCTAssertEqual(startedToolCall.arguments["query"]?.value as? String, "fallback")
        XCTAssertEqual(startedToolCall.providerContextValue(for: "session_thread_id"), "thread_fallback")
        XCTAssertEqual(startedToolCall.providerContextValue(for: "underlying_tool_use_id"), "underlying_fallback")
    }

    func testParseApprovalInteractionUsesToolNameFallbackForCommand() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        _ = try parse(
            #"{"type":"agent.tool_use","tool_use_id":"approval_fallback","tool_name":"shell","input":{"cmd":"touch file"},"evaluated_permission":"ask","working_directory":"/repo/subdir"}"#,
            state: &state
        )
        let idleResult = try parse(
            #"{"type":"session.status_idle","stop_reason":{"type":"requires_action","event_ids":["approval_fallback"]}}"#,
            state: &state
        )

        let interaction = try XCTUnwrap(idleResult.pendingInteraction)
        guard case .commandApproval(let approval) = interaction.kind else {
            return XCTFail("Expected command approval interaction")
        }
        XCTAssertEqual(interaction.itemID, "approval_fallback")
        XCTAssertEqual(interaction.providerContext["underlying_tool_use_id"], "approval_fallback")
        XCTAssertEqual(approval.command, "shell")
        XCTAssertEqual(approval.cwd, "/repo/subdir")
    }

    func testParseApprovalInteractionWaitsForRequiredActionIdle() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let askResult = try parse(
            #"{"type":"agent.tool_use","id":"approval_1","name":"shell","input":{"cmd":"rm tmp"},"evaluated_permission":"ask","cwd":"/repo","reason":"Needs permission","turn_id":"turn_1","tool_use_id":"underlying_1","session_thread_id":"thread_1"}"#,
            state: &state
        )
        XCTAssertTrue(askResult.events.isEmpty)
        XCTAssertNil(askResult.pendingInteraction)

        let idleResult = try parse(
            #"{"type":"session.status_idle","stop_reason":{"type":"requires_action","event_ids":["approval_1"]}}"#,
            state: &state
        )

        let interaction = try XCTUnwrap(idleResult.pendingInteraction)
        XCTAssertEqual(interaction.itemID, "approval_1")
        XCTAssertEqual(interaction.threadID, "sess_123")
        XCTAssertEqual(interaction.turnID, "turn_1")
        XCTAssertEqual(interaction.providerContext["session_thread_id"], "thread_1")
        XCTAssertEqual(interaction.providerContext["underlying_tool_use_id"], "underlying_1")
        XCTAssertContainsInteractionRequest(idleResult.events, itemID: "approval_1")

        guard case .commandApproval(let approval) = interaction.kind else {
            return XCTFail("Expected command approval interaction")
        }
        XCTAssertEqual(approval.command, "shell")
        XCTAssertEqual(approval.cwd, "/repo")
        XCTAssertEqual(approval.reason, "Needs permission")
        XCTAssertFalse(state.didReachIdle)
    }

    func testParseApprovalInteractionDequeuesOnlyRequiredPendingApproval() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        _ = try parse(
            #"{"type":"agent.tool_use","id":"approval_first","name":"shell","input":{"cmd":"first"},"evaluated_permission":"ask"}"#,
            state: &state
        )
        _ = try parse(
            #"{"type":"agent.tool_use","id":"approval_second","name":"shell","input":{"cmd":"second"},"evaluated_permission":"ask"}"#,
            state: &state
        )

        let idleResult = try parse(
            #"{"type":"session.status_idle","stop_reason":{"type":"requires_action","event_ids":["approval_second"]}}"#,
            state: &state
        )

        let interaction = try XCTUnwrap(idleResult.pendingInteraction)
        XCTAssertEqual(interaction.itemID, "approval_second")
        XCTAssertEqual(state.pendingApprovalInteractions.map(\.itemID), ["approval_first"])
        XCTAssertContainsInteractionRequest(idleResult.events, itemID: "approval_second")
        XCTAssertFalse(state.didReachIdle)
    }

    func testParseEventUsesNestedEventTypeFallback() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"event":{"type":"AGENT.MESSAGE"},"id":"msg_nested","text":"Nested event"}"#,
            state: &state
        )

        XCTAssertContainsMessageStart(result.events, id: "msg_nested")
        XCTAssertContainsTextDelta(result.events, text: "Nested event")
    }

    func testParseEventUsesEventTypeFallback() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"event_type":"AGENT.MESSAGE","id":"msg_event_type","text":"Event type"}"#,
            state: &state
        )

        XCTAssertContainsMessageStart(result.events, id: "msg_event_type")
        XCTAssertContainsTextDelta(result.events, text: "Event type")
    }

    func testParseEventUsesNestedSessionIDFallback() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_initial")

        let result = try parse(
            #"{"type":"session.status_running","session":{"id":"sess_nested","model":{"id":"claude-sonnet-4-6"}}}"#,
            state: &state
        )

        XCTAssertEqual(state.sessionID, "sess_nested")
        XCTAssertContainsSessionState(result.events, sessionID: "sess_nested", modelID: "claude-sonnet-4-6")
    }

    func testParseEventDoesNotEmitDuplicateSessionStateForUnchangedSessionID() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let result = try parse(
            #"{"type":"session.status_running","session_id":"sess_123","model_id":"claude-sonnet-4-6"}"#,
            state: &state
        )

        XCTAssertFalse(result.events.contains { event in
            guard case .claudeManagedSessionState = event else { return false }
            return true
        })
    }

    func testParseTerminatedSessionClosesOpenMessageOnce() throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        let messageResult = try parse(
            #"{"type":"agent.message","id":"msg_terminated","text":"Before termination"}"#,
            state: &state
        )
        let terminatedResult = try parse(
            #"{"type":"session.status_terminated"}"#,
            state: &state
        )
        let repeatedTerminatedResult = try parse(
            #"{"type":"session.deleted"}"#,
            state: &state
        )
        let events = messageResult.events + terminatedResult.events + repeatedTerminatedResult.events

        XCTAssertTrue(state.didReachIdle)
        XCTAssertTrue(state.didEmitMessageEnd)
        XCTAssertContainsMessageStart(events, id: "msg_terminated")
        XCTAssertEqual(messageEndEvents(in: events).count, 1)
    }

    func testParseSessionErrorThrowsProviderError() {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        XCTAssertThrowsError(try parse(
            #"{"type":"session.error","error":{"message":"Agent failed"}}"#,
            state: &state
        )) { error in
            guard case LLMError.providerError(let code, let message) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "claude_managed_agents_error")
            XCTAssertEqual(message, "Agent failed")
        }
    }

    func testParseSessionErrorUsesTopLevelMessageFallback() {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        XCTAssertThrowsError(try parse(
            #"{"type":"session.error","message":"Top-level failure"}"#,
            state: &state
        )) { error in
            guard case LLMError.providerError(let code, let message) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "claude_managed_agents_error")
            XCTAssertEqual(message, "Top-level failure")
        }
    }

    func testParseSessionErrorUsesDefaultMessageFallback() {
        var state = ClaudeManagedAgentsStreamState(sessionID: "sess_123")

        XCTAssertThrowsError(try parse(
            #"{"type":"session.error"}"#,
            state: &state
        )) { error in
            guard case LLMError.providerError(let code, let message) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "claude_managed_agents_error")
            XCTAssertEqual(message, "Claude Managed Agents returned an error event.")
        }
    }

    private func parse(
        _ json: String,
        state: inout ClaudeManagedAgentsStreamState,
        tools: [ToolDefinition] = []
    ) throws -> ClaudeManagedAgentsParsedEvent {
        try ClaudeManagedAgentStreamParsingSupport.parseEvent(json, state: &state, tools: tools)
    }

    private func searchActivities(in events: [StreamEvent]) -> [SearchActivity] {
        events.compactMap { event in
            guard case .searchActivity(let activity) = event else { return nil }
            return activity
        }
    }

    private func codexToolActivities(in events: [StreamEvent]) -> [CodexToolActivity] {
        events.compactMap { event in
            guard case .codexToolActivity(let activity) = event else { return nil }
            return activity
        }
    }

    private func toolCallStarts(in events: [StreamEvent]) -> [ToolCall] {
        events.compactMap { event in
            guard case .toolCallStart(let toolCall) = event else { return nil }
            return toolCall
        }
    }

    private func toolCallEnds(in events: [StreamEvent]) -> [ToolCall] {
        events.compactMap { event in
            guard case .toolCallEnd(let toolCall) = event else { return nil }
            return toolCall
        }
    }

    private func textDeltas(in events: [StreamEvent]) -> [String] {
        events.compactMap { event in
            guard case .contentDelta(.text(let text)) = event else { return nil }
            return text
        }
    }

    private func messageEndUsage(in events: [StreamEvent]) -> Usage? {
        guard let usage = messageEndEvents(in: events).last else { return nil }
        return usage
    }

    private func messageEndEvents(in events: [StreamEvent]) -> [Usage?] {
        events.compactMap { event -> Usage?? in
            guard case .messageEnd(let usage) = event else { return nil }
            return usage
        }
    }

    private func XCTAssertContainsSessionState(
        _ events: [StreamEvent],
        sessionID: String,
        modelID: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let found = events.contains { event in
            guard case .claudeManagedSessionState(let state) = event else { return false }
            return state.remoteSessionID == sessionID && state.remoteModelID == modelID
        }
        XCTAssertTrue(found, "Missing session state event", file: file, line: line)
    }

    private func XCTAssertContainsMessageStart(
        _ events: [StreamEvent],
        id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let found = events.contains { event in
            guard case .messageStart(let eventID) = event else { return false }
            return eventID == id
        }
        XCTAssertTrue(found, "Missing message start event", file: file, line: line)
    }

    private func XCTAssertContainsTextDelta(
        _ events: [StreamEvent],
        text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let found = events.contains { event in
            guard case .contentDelta(.text(let delta)) = event else { return false }
            return delta == text
        }
        XCTAssertTrue(found, "Missing text delta", file: file, line: line)
    }

    private func XCTAssertContainsInteractionRequest(
        _ events: [StreamEvent],
        itemID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let found = events.contains { event in
            guard case .codexInteractionRequest(let interaction) = event else { return false }
            return interaction.itemID == itemID
        }
        XCTAssertTrue(found, "Missing interaction request", file: file, line: line)
    }
}
