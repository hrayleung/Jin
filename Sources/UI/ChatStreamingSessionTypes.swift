import Foundation

extension ChatStreamingOrchestrator {
    struct SessionContext: Sendable {
        let conversationID: UUID
        let diagnosticRunID: String
        let providerID: String
        let providerConfig: ProviderConfig?
        let providerType: ProviderType?
        let modelID: String
        let modelNameSnapshot: String
        let resolvedModelSettings: ResolvedModelSettings?
        let messageSnapshots: [PersistedMessageSnapshot]
        let systemPrompt: String?
        let controlsToUse: GenerationControls
        let shouldTruncateMessages: Bool
        let maxHistoryMessages: Int?
        let modelContextWindow: Int
        let reservedOutputTokens: Int
        let mcpServerConfigs: [MCPServerConfig]
        let chatNamingTarget: (provider: ProviderConfig, modelID: String)?
        let shouldOfferBuiltinSearch: Bool
        let triggeredByUserSend: Bool
        let networkLogContext: NetworkDebugLogContext
    }

    struct SessionCallbacks {
        /// Persist an assistant message entity; returns the entity's UUID on success.
        let persistAssistantMessage: @MainActor (
            _ message: Message,
            _ providerID: String,
            _ modelID: String,
            _ modelName: String,
            _ metrics: ResponseMetrics?
        ) -> UUID?

        /// Persist a tool-result message entity.
        let persistToolMessage: @MainActor (
            _ message: Message
        ) -> Void

        /// Save Claude Managed Agents remote session state.
        let persistClaudeManagedSessionState: @MainActor (ClaudeManagedAgentSessionState) -> Void

        /// Save pending Claude Managed Agents custom tool results for the next turn.
        let persistClaudeManagedPendingToolResults: @MainActor (_ results: [ClaudeManagedAgentPendingToolResult]) -> Void

        /// Queue a managed agent interaction request for the user.
        let appendManagedAgentInteraction: @MainActor (ManagedAgentInteractionRequest) -> Void

        /// Merge search activities into a previously persisted assistant message.
        let mergeSearchActivities: @MainActor (_ messageID: UUID, _ activities: [SearchActivity]) -> Void

        /// Optionally auto-rename the conversation after the first assistant reply.
        let maybeAutoRename: @MainActor (
            _ provider: ProviderConfig,
            _ modelID: String,
            _ history: [Message],
            _ assistantMessage: Message
        ) async -> Void

        /// Display an error to the user.
        let showError: @MainActor (String) -> Void

        /// End the streaming session (called when tool calls are empty after persisting assistant message).
        let endStreamingSession: @MainActor () -> Void

        /// Final cleanup: notify completion and end session.
        let onSessionEnd: @MainActor (_ shouldNotify: Bool, _ preview: String?) -> Void
    }

    struct PreparedSession {
        let providerConfig: ProviderConfig
        let adapter: any LLMProviderAdapter
        let history: [Message]
        let requestControls: GenerationControls
        let allTools: [ToolDefinition]
        let mcpRoutes: ToolRouteSnapshot
        let builtinRoutes: BuiltinToolRouteSnapshot
        let maxToolIterations: Int
    }

}
