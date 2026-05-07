import Foundation

extension ChatStreamingOrchestrator {
    static func deniedAgentToolExecution(
        for call: ToolCall,
        durationSeconds: Double
    ) -> (toolResult: ToolResult, outputLine: String, activity: CodexToolActivity) {
        (
            toolResult: toolResult(
                for: call,
                content: deniedToolResultContent(),
                isError: true,
                durationSeconds: durationSeconds
            ),
            outputLine: deniedToolOutputLine(toolName: call.name),
            activity: deniedAgentToolActivity(for: call)
        )
    }

    static func runningAgentToolActivity(for call: ToolCall) -> CodexToolActivity {
        CodexToolActivity(
            id: call.id,
            toolName: call.name,
            status: .running,
            arguments: call.arguments
        )
    }

    static func deniedAgentToolActivity(for call: ToolCall) -> CodexToolActivity {
        CodexToolActivity(
            id: call.id,
            toolName: call.name,
            status: .failed,
            arguments: call.arguments,
            output: "Denied by user"
        )
    }

    static func completedAgentToolActivity(
        for call: ToolCall,
        result: MCPToolCallResult,
        normalizedContent: String
    ) -> CodexToolActivity {
        CodexToolActivity(
            id: call.id,
            toolName: call.name,
            status: result.isError ? .failed : .completed,
            arguments: call.arguments,
            output: agentToolActivityOutput(from: normalizedContent),
            rawOutputPath: result.rawOutputPath
        )
    }

    static func failedAgentToolActivity(
        for call: ToolCall,
        content: String
    ) -> CodexToolActivity {
        CodexToolActivity(
            id: call.id,
            toolName: call.name,
            status: .failed,
            arguments: call.arguments,
            output: agentToolActivityOutput(from: content),
            rawOutputPath: nil
        )
    }

    static func agentToolActivityOutput(from content: String) -> String {
        String(content.prefix(4_096))
    }

    static func agentToolApprovalDecision(
        for call: ToolCall,
        controls: AgentModeControls,
        approvalStore: AgentApprovalSessionStore,
        callbacks: SessionCallbacks,
        threadID: UUID
    ) async throws -> AgentToolApprovalDecision {
        let preparedShellExecution: AgentToolHub.PreparedShellExecution?
        if call.name == AgentToolNames.shellExecute {
            preparedShellExecution = try await AgentToolHub.shared.prepareShellExecution(
                arguments: call.arguments,
                controls: controls
            )
        } else {
            preparedShellExecution = nil
        }

        let preparation = AgentToolExecutionPreparation(
            controls: controls,
            preparedShellExecution: preparedShellExecution
        )

        // Approvals are keyed on the user's original tool intent, not RTK's
        // internal rewrite. executeShell() separately validates that rewrite.
        let approvalKey = AgentToolApprovalSupport.sessionKey(
            functionName: call.name,
            arguments: call.arguments,
            controls: controls
        )
        let needsApproval = await AgentToolApprovalSupport.needsApproval(
            functionName: call.name,
            arguments: call.arguments,
            controls: controls,
            approvalKey: approvalKey,
            approvalStore: approvalStore
        )

        guard needsApproval else {
            return .approved(preparation)
        }

        let approvalRequest = AgentToolApprovalSupport.makeRequest(
            functionName: call.name,
            arguments: call.arguments,
            controls: controls
        )
        await MainActor.run {
            callbacks.appendAgentApproval(approvalRequest, threadID)
        }

        let choice = await approvalRequest.waitForResponse()
        switch choice {
        case .deny:
            return .denied
        case .cancel:
            return .cancelled
        case .allow:
            return .approved(preparation)
        case .allowForSession:
            if let approvalKey {
                await approvalStore.approve(key: approvalKey)
            }
            return .approved(preparation)
        }
    }
}
