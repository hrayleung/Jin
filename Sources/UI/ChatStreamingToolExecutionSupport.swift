import Foundation

extension ChatStreamingOrchestrator {
    static func toolExecutionRoute(
        for call: ToolCall,
        builtinRoutes: BuiltinToolRouteSnapshot,
        agentRoutes: AgentToolRouteSnapshot
    ) -> ToolExecutionRoute {
        if agentRoutes.contains(functionName: call.name) {
            return .agent
        }
        if builtinRoutes.contains(functionName: call.name) {
            return .builtin
        }
        return .mcp
    }

    static func executableToolCalls(from toolCalls: [ToolCall]) -> [ToolCall] {
        toolCalls.filter { !isGoogleProviderNativeToolName($0.name) }
    }

    static func toolOutputLine(
        toolName: String,
        content: String,
        isError: Bool
    ) -> String {
        if isError {
            return "Tool \(toolName) failed:\n\(content)"
        }

        return "Tool \(toolName):\n\(content)"
    }

    static func deniedToolOutputLine(toolName: String) -> String {
        "Tool \(toolName) denied by user."
    }

    static func toolResult(
        for call: ToolCall,
        content: String,
        isError: Bool,
        durationSeconds: Double,
        rawOutputPath: String? = nil
    ) -> ToolResult {
        ToolResult(
            toolCallID: call.id,
            toolName: call.name,
            content: content,
            isError: isError,
            signature: call.signature,
            durationSeconds: durationSeconds,
            rawOutputPath: rawOutputPath
        )
    }

    static func toolResult(
        for call: ToolCall,
        result: MCPToolCallResult,
        durationSeconds: Double
    ) -> ToolResult {
        let normalizedContent = normalizedToolResultContent(for: call, result: result)
        return toolResult(
            for: call,
            content: normalizedContent,
            isError: result.isError,
            durationSeconds: durationSeconds,
            rawOutputPath: result.rawOutputPath
        )
    }

    static func normalizedToolResultContent(
        for call: ToolCall,
        result: MCPToolCallResult
    ) -> String {
        ToolSearchActivityFactory.normalizedToolResultContent(
            result.text,
            toolName: call.name,
            isError: result.isError
        )
    }

    static func toolExecutionFailureContent(
        for call: ToolCall,
        error: Error
    ) -> String {
        let normalizedError = ToolSearchActivityFactory.normalizedToolResultContent(
            error.localizedDescription,
            toolName: call.name,
            isError: true
        )
        return "Tool execution failed: \(normalizedError). You may retry this tool call with corrected arguments."
    }

    static func toolSearchActivity(
        route: ToolExecutionRoute,
        call: ToolCall,
        toolResultText: String,
        isError: Bool,
        builtinRoutes: BuiltinToolRouteSnapshot
    ) -> SearchActivity? {
        guard route == .builtin else { return nil }
        return ToolSearchActivityFactory.activityFromToolResult(
            call: call,
            toolResultText: toolResultText,
            isError: isError,
            providerOverride: builtinRoutes.provider(for: call.name)
        )
    }

    static func toolSearchStartActivity(
        for call: ToolCall,
        builtinRoutes: BuiltinToolRouteSnapshot
    ) -> SearchActivity? {
        guard builtinRoutes.contains(functionName: call.name) else { return nil }
        return ToolSearchActivityFactory.activityForToolCallStart(
            call: call,
            providerOverride: builtinRoutes.provider(for: call.name)
        )
    }

    static func deniedToolResultContent() -> String {
        "User denied this tool call. Do not retry this exact action without permission."
    }
}
