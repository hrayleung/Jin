import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Auxiliary Controls: Capability Queries, Badges, Help Text & Bindings

extension ChatView {

    // MARK: - Model Info

    var selectedModelInfo: ModelInfo? {
        guard let model = ChatModelCapabilitySupport.resolvedModelInfo(
            modelID: conversationEntity.modelID,
            providerEntity: currentProvider,
            providerType: providerType,
            availableModels: currentProvider?.allModels
        ) else {
            return nil
        }

        return ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: providerType
        )
    }

    var resolvedModelSettings: ResolvedModelSettings? {
        guard let model = selectedModelInfo else { return nil }
        return ModelSettingsResolver.resolve(model: model, providerType: providerType)
    }

    var lowerModelID: String {
        conversationEntity.modelID.lowercased()
    }

    func resolvedModelInfo(
        for modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> ModelInfo? {
        ChatModelCapabilitySupport.resolvedModelInfo(
            modelID: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: availableModels
        )
    }

    func effectiveModelID(
        for modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> String {
        ChatModelCapabilitySupport.effectiveModelID(
            modelID: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: availableModels
        )
    }

    func migrateThreadModelIDIfNeeded(
        _ thread: ConversationModelThreadEntity,
        resolvedModelID: String
    ) {
        guard resolvedModelID != thread.modelID else { return }
        thread.modelID = resolvedModelID
        if conversationEntity.activeThreadID == thread.id {
            conversationEntity.modelID = resolvedModelID
        }
        conversationEntity.updatedAt = Date()
        try? modelContext.save()
    }

    func canonicalModelID(for providerID: String, modelID: String) -> String {
        let providerEntity = providers.first(where: { $0.id == providerID })
        let providerType = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) }
        return effectiveModelID(
            for: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: providerEntity?.allModels
        )
    }

    func canonicalizeThreadModelIDIfNeeded(_ thread: ConversationModelThreadEntity) {
        let resolved = canonicalModelID(for: thread.providerID, modelID: thread.modelID)
        migrateThreadModelIDIfNeeded(thread, resolvedModelID: resolved)
    }

    func normalizedSelectedModelInfo(_ model: ModelInfo) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: providerType
        )
    }

    func normalizedFireworksModelInfo(_ model: ModelInfo) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedFireworksModelInfo(model)
    }

    func normalizedModelInfo(_ model: ModelInfo, for providerType: ProviderType?) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedSelectedModelInfo(model, providerType: providerType)
    }

    // MARK: - Media Generation Capability

    var isImageGenerationModelID: Bool {
        ChatModelCapabilitySupport.isImageGenerationModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            openAIImageGenerationModelIDs: Self.openAIImageGenerationModelIDs,
            xAIImageGenerationModelIDs: Self.xAIImageGenerationModelIDs,
            geminiImageGenerationModelIDs: Self.geminiImageGenerationModelIDs
        )
    }

    var isVideoGenerationModelID: Bool {
        ChatModelCapabilitySupport.isVideoGenerationModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            xAIVideoGenerationModelIDs: Self.xAIVideoGenerationModelIDs,
            googleVideoGenerationModelIDs: Self.googleVideoGenerationModelIDs
        )
    }

    var supportsNativePDF: Bool {
        ChatModelCapabilitySupport.supportsNativePDF(
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            providerType: providerType,
            resolvedModelSettings: resolvedModelSettings,
            lowerModelID: lowerModelID
        )
    }

    var supportsVision: Bool {
        ChatModelCapabilitySupport.supportsVision(
            resolvedModelSettings: resolvedModelSettings,
            supportsImageGenerationControl: supportsImageGenerationControl,
            supportsVideoGenerationControl: supportsVideoGenerationControl
        )
    }

    var supportsAudioInput: Bool {
        ChatModelCapabilitySupport.supportsAudioInput(
            isMistralTranscriptionOnlyModelID: isMistralTranscriptionOnlyModelID,
            resolvedModelSettings: resolvedModelSettings,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            providerType: providerType,
            lowerModelID: lowerModelID,
            openAIAudioInputModelIDs: Self.openAIAudioInputModelIDs,
            mistralAudioInputModelIDs: Self.mistralAudioInputModelIDs,
            geminiAudioInputModelIDs: Self.geminiAudioInputModelIDs,
            compatibleAudioInputModelIDs: Self.compatibleAudioInputModelIDs,
            fireworksAudioInputModelIDs: Self.fireworksAudioInputModelIDs
        )
    }

    var isMistralTranscriptionOnlyModelID: Bool {
        ChatModelCapabilitySupport.isMistralTranscriptionOnlyModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            mistralTranscriptionOnlyModelIDs: Self.mistralTranscriptionOnlyModelIDs
        )
    }

    var supportsImageGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.imageGeneration) == true || isImageGenerationModelID
    }

    var supportsVideoGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.videoGeneration) == true || isVideoGenerationModelID
    }

    var supportsMediaGenerationControl: Bool {
        supportsImageGenerationControl || supportsVideoGenerationControl
    }

    var supportsImageGenerationWebSearch: Bool {
        ChatModelCapabilitySupport.supportsImageGenerationWebSearch(
            supportsImageGenerationControl: supportsImageGenerationControl,
            resolvedModelSettings: resolvedModelSettings,
            providerType: providerType,
            conversationModelID: conversationEntity.modelID
        )
    }

    var supportsPDFProcessingControl: Bool {
        guard providerType != .codexAppServer else { return false }
        return true
    }

    var supportsCurrentModelImageSizeControl: Bool {
        ChatModelCapabilitySupport.supportsCurrentModelImageSizeControl(lowerModelID: lowerModelID)
    }

    var supportedCurrentModelImageAspectRatios: [ImageAspectRatio] {
        ChatModelCapabilitySupport.supportedCurrentModelImageAspectRatios(lowerModelID: lowerModelID)
    }

    var supportedCurrentModelImageSizes: [ImageOutputSize] {
        ChatModelCapabilitySupport.supportedCurrentModelImageSizes(lowerModelID: lowerModelID)
    }

    var isImageGenerationConfigured: Bool {
        ChatModelCapabilitySupport.isImageGenerationConfigured(
            providerType: providerType,
            controls: controls
        )
    }

    var imageGenerationBadgeText: String? {
        ChatModelCapabilitySupport.imageGenerationBadgeText(
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            controls: controls,
            isImageGenerationConfigured: isImageGenerationConfigured
        )
    }

    var imageGenerationHelpText: String {
        ChatModelCapabilitySupport.imageGenerationHelpText(
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            controls: controls,
            isImageGenerationConfigured: isImageGenerationConfigured
        )
    }

    var isVideoGenerationConfigured: Bool {
        ChatModelCapabilitySupport.isVideoGenerationConfigured(
            providerType: providerType,
            controls: controls
        )
    }

    var videoGenerationBadgeText: String? {
        ChatModelCapabilitySupport.videoGenerationBadgeText(
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            providerType: providerType,
            controls: controls,
            isVideoGenerationConfigured: isVideoGenerationConfigured
        )
    }

    var videoGenerationHelpText: String {
        ChatModelCapabilitySupport.videoGenerationHelpText(
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            providerType: providerType,
            controls: controls,
            isVideoGenerationConfigured: isVideoGenerationConfigured
        )
    }

    // MARK: - PDF Processing

    var resolvedPDFProcessingMode: PDFProcessingMode {
        resolvedPDFProcessingMode(for: controls, supportsNativePDF: supportsNativePDF)
    }

    var defaultPDFProcessingFallbackMode: PDFProcessingMode {
        ChatModelCapabilitySupport.defaultPDFProcessingFallbackMode(
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            mistralOCRConfigured: mistralOCRConfigured,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            deepSeekOCRConfigured: deepSeekOCRConfigured
        )
    }

    func isPDFProcessingModeAvailable(_ mode: PDFProcessingMode) -> Bool {
        isPDFProcessingModeAvailable(mode, supportsNativePDF: supportsNativePDF)
    }

    func isPDFProcessingModeAvailable(_ mode: PDFProcessingMode, supportsNativePDF: Bool) -> Bool {
        ChatModelCapabilitySupport.isPDFProcessingModeAvailable(
            mode,
            supportsNativePDF: supportsNativePDF,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled
        )
    }

    func resolvedPDFProcessingMode(for controls: GenerationControls, supportsNativePDF: Bool) -> PDFProcessingMode {
        ChatModelCapabilitySupport.resolvedPDFProcessingMode(
            controls: controls,
            supportsNativePDF: supportsNativePDF,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled
        )
    }

    var pdfProcessingBadgeText: String? {
        switch resolvedPDFProcessingMode {
        case .native:
            return nil
        case .mistralOCR:
            return "OCR"
        case .deepSeekOCR:
            return "DS"
        case .macOSExtract:
            return "mac"
        }
    }

    var pdfProcessingHelpText: String {
        switch resolvedPDFProcessingMode {
        case .native:
            return "PDF handling: Native"
        case .mistralOCR:
            return mistralOCRConfigured ? "PDF handling: Mistral OCR" : "PDF handling: Mistral OCR (API key required)"
        case .deepSeekOCR:
            return deepSeekOCRConfigured ? "PDF handling: DeepSeek OCR (DeepInfra)" : "PDF handling: DeepSeek OCR (API key required)"
        case .macOSExtract:
            return "PDF handling: macOS Extract"
        }
    }

    // MARK: - Reasoning

    var selectedReasoningConfig: ModelReasoningConfig? {
        if providerType == .vertexai,
           (lowerModelID == "gemini-3-pro-image-preview"
               || lowerModelID == "gemini-3.1-flash-image-preview") {
            return nil
        }
        return resolvedModelSettings?.reasoningConfig
    }

    var isReasoningEnabled: Bool {
        if reasoningMustRemainEnabled {
            return true
        }
        if providerType == .fireworks, isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return true
        }
        return controls.reasoning?.enabled == true
    }

    var supportsReasoningControl: Bool {
        guard let config = selectedReasoningConfig else { return false }
        return config.type != .none
    }

    var supportsReasoningDisableToggle: Bool {
        guard supportsReasoningControl else { return false }
        return !reasoningMustRemainEnabled
    }

    var reasoningMustRemainEnabled: Bool {
        resolvedModelSettings?.reasoningCanDisable == false
    }

    // MARK: - Web Search

    var isWebSearchEnabled: Bool {
        guard supportsWebSearchControl else { return false }
        switch providerType {
        case .perplexity:
            return controls.webSearch?.enabled ?? true
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
             .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini, .vertexai, .none:
            return controls.webSearch?.enabled == true
        }
    }

    var supportsNativeWebSearchControl: Bool {
        guard providerType != .codexAppServer else { return false }

        if supportsMediaGenerationControl {
            if supportsImageGenerationControl {
                return supportsImageGenerationWebSearch
            }
            return false
        }

        if let resolvedModelSettings {
            return resolvedModelSettings.supportsWebSearch
        }

        return ModelCapabilityRegistry.supportsWebSearch(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    var modelSupportsBuiltinSearchPluginControl: Bool {
        guard providerType != .codexAppServer else { return false }
        guard !supportsMediaGenerationControl else { return false }
        guard resolvedModelSettings?.capabilities.contains(.toolCalling) == true else { return false }
        return true
    }

    var supportsBuiltinSearchPluginControl: Bool {
        guard modelSupportsBuiltinSearchPluginControl else { return false }
        guard webSearchPluginEnabled, webSearchPluginConfigured else { return false }
        return true
    }

    var supportsSearchEngineModeSwitch: Bool {
        supportsNativeWebSearchControl && supportsBuiltinSearchPluginControl
    }

    var prefersJinSearchEngine: Bool {
        controls.searchPlugin?.preferJinSearch == true
    }

    var usesBuiltinSearchPlugin: Bool {
        guard supportsBuiltinSearchPluginControl else { return false }
        if supportsNativeWebSearchControl {
            return prefersJinSearchEngine
        }
        return true
    }

    var modelSupportsWebSearchControl: Bool {
        supportsNativeWebSearchControl || modelSupportsBuiltinSearchPluginControl
    }

    var supportsWebSearchControl: Bool {
        supportsNativeWebSearchControl || supportsBuiltinSearchPluginControl
    }

    var effectiveSearchPluginProvider: SearchPluginProvider {
        if let provider = controls.searchPlugin?.provider {
            return provider
        }
        return WebSearchPluginSettingsStore.load().defaultProvider
    }

    // MARK: - Code Execution

    var supportsCodeExecutionControl: Bool {
        guard let modelID = selectedModelInfo?.id else { return false }
        return ModelCapabilityRegistry.supportsCodeExecution(for: providerType, modelID: modelID)
    }

    var isCodeExecutionEnabled: Bool {
        controls.codeExecution?.enabled == true
    }

    var hasCodeExecutionConfiguration: Bool {
        providerType == .openai || providerType == .openaiWebSocket || providerType == .anthropic
    }

    var codeExecutionEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.codeExecution?.enabled ?? false },
            set: { enabled in
                var updated = controls.codeExecution ?? CodeExecutionControls()
                updated.enabled = enabled
                controls.codeExecution = updated
                persistControlsToConversation()
            }
        )
    }

    var isCodeExecutionDraftValid: Bool {
        guard (providerType == .openai || providerType == .openaiWebSocket),
              codeExecutionOpenAIUseExistingContainer else {
            return true
        }
        return codeExecutionDraft.openAI?.normalizedExistingContainerID != nil
    }

    var parsedCodeExecutionOpenAIFileIDsDraft: [String] {
        codeExecutionOpenAIFileIDsDraft
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var codeExecutionBadgeText: String? {
        guard isCodeExecutionEnabled else { return nil }

        switch providerType {
        case .openai, .openaiWebSocket:
            if controls.codeExecution?.openAI?.normalizedExistingContainerID != nil {
                return "reuse"
            }
            return controls.codeExecution?.openAI?.container?.normalizedMemoryLimit
        case .anthropic:
            return controls.codeExecution?.anthropic?.normalizedContainerID == nil ? nil : "reuse"
        default:
            return nil
        }
    }

    var codeExecutionHelpText: String {
        guard isCodeExecutionEnabled else { return "Code Execution: Off" }

        switch providerType {
        case .openai, .openaiWebSocket:
            if let containerID = controls.codeExecution?.openAI?.normalizedExistingContainerID {
                return "Code Execution: Reuse \(containerID)"
            }
            if let memoryLimit = controls.codeExecution?.openAI?.container?.normalizedMemoryLimit {
                return "Code Execution: Auto container (\(memoryLimit))"
            }
            return "Code Execution: Auto container"
        case .anthropic:
            if controls.codeExecution?.anthropic?.normalizedContainerID != nil {
                return "Code Execution: Reuse container"
            }
            return "Code Execution: On"
        case .vertexai:
            return "Code Execution: On (no file I/O in sandbox)"
        default:
            return "Code Execution: On"
        }
    }

    // MARK: - Google Maps

    var supportsGoogleMapsControl: Bool {
        guard let modelID = selectedModelInfo?.id else { return false }
        return ModelCapabilityRegistry.supportsGoogleMaps(for: providerType, modelID: modelID)
    }

    var isGoogleMapsEnabled: Bool {
        controls.googleMaps?.enabled == true
    }

    var googleMapsBadgeText: String? {
        guard isGoogleMapsEnabled else { return nil }
        if controls.googleMaps?.hasLocation == true {
            return "Loc"
        }
        return nil
    }

    var googleMapsHelpText: String {
        guard isGoogleMapsEnabled else { return "Google Maps: Off" }
        if controls.googleMaps?.hasLocation == true {
            return "Google Maps: On (with location)"
        }
        return "Google Maps: On"
    }

    var googleMapsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.googleMaps?.enabled == true },
            set: { enabled in
                var updated = controls.googleMaps ?? GoogleMapsControls(enabled: enabled)
                updated.enabled = enabled
                controls.googleMaps = updated.isEmpty ? nil : updated
                persistControlsToConversation()
            }
        )
    }

    // MARK: - MCP Tools

    var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled == true
    }

    var supportsMCPToolsControl: Bool {
        guard providerType != .codexAppServer else { return false }
        guard !supportsMediaGenerationControl else { return false }
        return resolvedModelSettings?.capabilities.contains(.toolCalling) == true
    }

    var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedMCPServerIDs: Set<String> {
        ChatAuxiliaryControlSupport.selectedMCPServerIDs(
            controls: controls,
            eligibleServers: eligibleMCPServers
        )
    }

    var mcpServerMenuItems: [MCPServerMenuItem] {
        eligibleMCPServers.map { server in
            MCPServerMenuItem(
                id: server.id,
                name: server.name,
                isOn: mcpServerSelectionBinding(serverID: server.id)
            )
        }
    }

    // MARK: - Context Cache

    var effectiveContextCacheMode: ContextCacheMode {
        if let mode = controls.contextCache?.mode {
            return mode
        }
        if providerType == .anthropic {
            return .implicit
        }
        return .off
    }

    var isContextCacheEnabled: Bool {
        effectiveContextCacheMode != .off
    }

    var supportsContextCacheControl: Bool {
        false
    }

    var supportsExplicitContextCacheMode: Bool {
        switch providerType {
        case .gemini, .vertexai:
            return true
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .xai, .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return false
        }
    }

    var supportsContextCacheStrategy: Bool {
        providerType == .anthropic
    }

    var supportsContextCacheTTL: Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .xai:
            return true
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return false
        }
    }

    var contextCacheSupportsAdvancedOptions: Bool {
        supportsContextCacheTTL || providerType == .openai || providerType == .xai
    }

    var contextCacheSummaryText: String {
        switch providerType {
        case .gemini, .vertexai:
            return "Use implicit caching for normal chats, or explicit caching with a cached content resource for long reusable context."
        case .anthropic:
            return "Anthropic caches tagged prompt blocks. Keep stable system/tool prefixes to improve cache hit rates."
        case .openai, .openaiWebSocket:
            return "OpenAI uses prompt cache hints. A stable key and retention hint can improve reuse across similar prompts."
        case .xai:
            return "xAI supports prompt cache hints and optional conversation scoping for continuity across related turns."
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan,
             .fireworks, .cerebras, .sambanova, .none:
            return "Context cache controls are only available for providers with native prompt caching support."
        }
    }

    var contextCacheGuidanceText: String {
        switch providerType {
        case .gemini, .vertexai:
            return "Explicit mode requires a valid cached content resource name. Keep it stable across requests to reuse cached tokens."
        case .openai, .openaiWebSocket, .xai:
            return "Use a stable cache key when your prompt prefix is consistent."
        case .anthropic:
            return "For best results, keep system prompts and tool descriptions stable so Anthropic can reuse cacheable blocks."
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan,
             .fireworks, .cerebras, .sambanova, .none:
            return "Use explicit mode for Gemini/Vertex cached content resources. Other providers use implicit cache hints."
        }
    }

    func automaticContextCacheControls(
        providerType: ProviderType?,
        modelID: String,
        modelCapabilities: ModelCapability?
    ) -> ContextCacheControls? {
        ChatAuxiliaryControlSupport.automaticContextCacheControls(
            providerType: providerType,
            modelID: modelID,
            modelCapabilities: modelCapabilities,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            conversationID: conversationEntity.id
        )
    }

    var contextCacheLabel: String {
        let mode = effectiveContextCacheMode
        switch mode {
        case .off:
            return "Off"
        case .implicit:
            return "Implicit"
        case .explicit:
            if let name = controls.contextCache?.cachedContentName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return "Explicit (\(name))"
            }
            return "Explicit"
        }
    }

    var contextCacheBadgeText: String? {
        guard supportsContextCacheControl, isContextCacheEnabled else { return nil }
        switch effectiveContextCacheMode {
        case .off:
            return nil
        case .implicit:
            return "I"
        case .explicit:
            return "E"
        }
    }

    var contextCacheHelpText: String {
        guard supportsContextCacheControl else { return "Context Cache: Not supported" }
        guard isContextCacheEnabled else { return "Context Cache: Off" }
        return "Context Cache: \(contextCacheLabel)"
    }

    // MARK: - Codex & Service Tier

    var supportsCodexSessionControl: Bool {
        providerType == .codexAppServer
    }

    var supportsOpenAIServiceTierControl: Bool {
        guard !supportsMediaGenerationControl else { return false }
        return providerType == .openai || providerType == .openaiWebSocket
    }

    var isAgentModeConfigured: Bool {
        AppPreferences.isPluginEnabled("agent_mode")
    }

    var codexWorkingDirectory: String? {
        controls.codexWorkingDirectory
    }

    var codexSessionOverrideCount: Int {
        controls.codexActiveOverrideCount
    }

    var codexSessionBadgeText: String? {
        guard codexSessionOverrideCount > 0 else { return nil }
        return controls.codexSandboxMode.badgeText
    }

    // MARK: - Help Text & Labels

    var reasoningHelpText: String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .gemini, .vertexai:
            return "Thinking: \(reasoningLabel)"
        case .perplexity:
            return "Reasoning: \(reasoningLabel)"
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return "Reasoning: \(reasoningLabel)"
        }
    }

    var webSearchHelpText: String {
        guard supportsWebSearchControl else { return "Web Search: Not supported" }
        guard isWebSearchEnabled else { return "Web Search: Off" }
        return "Web Search: \(webSearchLabel)"
    }

    var openAIServiceTierHelpText: String {
        guard supportsOpenAIServiceTierControl else { return "Service Tier: Not supported" }
        return "Service Tier: \(openAIServiceTierLabel)"
    }

    var mcpToolsHelpText: String {
        guard supportsMCPToolsControl else { return "MCP Tools: Not supported" }
        guard isMCPToolsEnabled else { return "MCP Tools: Off" }
        let count = selectedMCPServerIDs.count
        if count == 0 { return "MCP Tools: On (no servers)" }
        return "MCP Tools: On (\(count) server\(count == 1 ? "" : "s"))"
    }

    var codexSessionHelpText: String {
        guard supportsCodexSessionControl else { return "Codex Session: Not supported" }

        var segments: [String] = ["Sandbox: \(controls.codexSandboxMode.displayName)"]
        if let workingDirectory = controls.codexWorkingDirectory {
            segments.append("Working Directory: \(workingDirectory)")
        } else {
            segments.append("Working Directory: app-server default")
        }
        if let personality = controls.codexPersonality {
            segments.append("Personality: \(personality.displayName)")
        }

        return "Codex Session: " + segments.joined(separator: " \u{00B7} ")
    }

    var webSearchLabel: String {
        if usesBuiltinSearchPlugin {
            let provider = effectiveSearchPluginProvider.displayName
            if let maxResults = controls.searchPlugin?.maxResults {
                return "\(provider) \u{00B7} \(maxResults) results"
            }
            return provider
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            return (controls.webSearch?.contextSize ?? .medium).displayName
        case .perplexity:
            return (controls.webSearch?.contextSize ?? .low).displayName
        case .xai:
            return webSearchSourcesLabel
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .anthropic,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return "On"
        }
    }

    var openAIServiceTierLabel: String {
        controls.openAIServiceTier?.displayName ?? "Auto"
    }

    var webSearchSourcesLabel: String {
        let sources = Set(controls.webSearch?.sources ?? [])
        if sources.isEmpty { return "On" }
        if sources == [.web] { return "Web" }
        if sources == [.x] { return "X" }
        return "Web + X"
    }

    // MARK: - Badge Text

    var reasoningBadgeText: String? {
        guard supportsReasoningControl, isReasoningEnabled else { return nil }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return nil }

        switch reasoningType {
        case .budget:
            switch controls.reasoning?.budgetTokens {
            case 1024: return "L"
            case 2048: return "M"
            case 4096: return "H"
            case 8192: return "X"
            default: return "On"
            }
        case .effort:
            guard let effort = controls.reasoning?.effort else { return "On" }
            switch effort {
            case .none: return nil
            case .minimal: return "Min"
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            case .xhigh: return "X"
            }
        case .toggle:
            return "On"
        case .none:
            return nil
        }
    }

    var openAIServiceTierBadgeText: String? {
        guard supportsOpenAIServiceTierControl else { return nil }
        return controls.openAIServiceTier?.badgeText
    }

    var webSearchBadgeText: String? {
        guard supportsWebSearchControl, isWebSearchEnabled else { return nil }

        if usesBuiltinSearchPlugin {
            return effectiveSearchPluginProvider.shortBadge
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .perplexity:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .xai:
            let sources = Set(controls.webSearch?.sources ?? [])
            if sources == [.web] { return "W" }
            if sources == [.x] { return "X" }
            if sources.contains(.web), sources.contains(.x) { return "W+X" }
            return "On"
        case .anthropic:
            return "On"
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return "On"
        }
    }

    var mcpToolsBadgeText: String? {
        guard supportsMCPToolsControl, isMCPToolsEnabled else { return nil }
        let count = selectedMCPServerIDs.count
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    // MARK: - PDF Processing Menu

    func setPDFProcessingMode(_ mode: PDFProcessingMode) {
        guard isPDFProcessingModeAvailable(mode) else { return }
        controls.pdfProcessingMode = (mode == .native) ? nil : mode
        persistControlsToConversation()
    }

    @ViewBuilder
    var pdfProcessingMenuContent: some View {
        if supportsNativePDF {
            Button { setPDFProcessingMode(.native) } label: { menuItemLabel("Native", isSelected: resolvedPDFProcessingMode == .native) }
        }

        if mistralOCRPluginEnabled {
            Button { setPDFProcessingMode(.mistralOCR) } label: { menuItemLabel("Mistral OCR", isSelected: resolvedPDFProcessingMode == .mistralOCR) }
        }

        if deepSeekOCRPluginEnabled {
            Button { setPDFProcessingMode(.deepSeekOCR) } label: { menuItemLabel("DeepSeek OCR (DeepInfra)", isSelected: resolvedPDFProcessingMode == .deepSeekOCR) }
        }

        Button { setPDFProcessingMode(.macOSExtract) } label: { menuItemLabel("macOS Extract", isSelected: resolvedPDFProcessingMode == .macOSExtract) }

        if resolvedPDFProcessingMode == .mistralOCR, !mistralOCRConfigured {
            Divider()
            Text("Set API key in Settings \u{2192} Plugins \u{2192} Mistral OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if resolvedPDFProcessingMode == .deepSeekOCR, !deepSeekOCRConfigured {
            Divider()
            Text("Set API key in Settings \u{2192} Plugins \u{2192} DeepSeek OCR (DeepInfra).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !mistralOCRPluginEnabled && !deepSeekOCRPluginEnabled {
            Divider()
            Text("OCR plugins are turned off. Enable them in Settings \u{2192} Plugins to show OCR modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Composer Helpers

    var trimmedMessageText: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRemoteVideoInputURLText: String {
        remoteVideoInputURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var supportsExplicitRemoteVideoURLInput: Bool {
        supportsVideoGenerationControl && providerType == .xai
    }

    var canSendDraft: Bool {
        (!trimmedMessageText.isEmpty || !draftAttachments.isEmpty) && !isImportingDropAttachments
    }

    var assistantDisplayName: String {
        conversationEntity.assistant?.displayName ?? "Assistant"
    }

    var speechToTextManagerActive: Bool {
        speechToTextManager.isRecording || speechToTextManager.isTranscribing
    }

    var speechToTextSystemImageName: String {
        if speechToTextManager.isTranscribing { return "waveform" }
        if speechToTextManager.isRecording { return "mic.fill" }
        return "mic"
    }

    var speechToTextActiveColor: Color {
        speechToTextManager.isRecording ? .red : .accentColor
    }

    var speechToTextBadgeText: String? {
        speechToTextManager.isTranscribing ? "\u{2026}" : nil
    }

    var speechToTextUsesAudioAttachment: Bool {
        sttAddRecordingAsFile && supportsAudioInput
    }

    var speechToTextReadyForCurrentMode: Bool {
        speechToTextUsesAudioAttachment || speechToTextConfigured
    }

    var speechToTextHelpText: String {
        if speechToTextManager.isTranscribing {
            return speechToTextUsesAudioAttachment ? "Attaching audio\u{2026}" : "Transcribing\u{2026}"
        }
        if speechToTextManager.isRecording {
            return speechToTextUsesAudioAttachment ? "Stop recording and attach audio" : "Stop recording"
        }
        if !speechToTextPluginEnabled { return "Speech to Text is turned off in Settings \u{2192} Plugins" }
        if speechToTextUsesAudioAttachment {
            return "Record audio and attach it to the draft message"
        }
        if sttAddRecordingAsFile && !supportsAudioInput {
            if speechToTextConfigured {
                return "Current model doesn't support audio input; using transcription fallback."
            }
            return "Current model doesn't support audio input. Configure Speech to Text for transcription fallback."
        }
        if !speechToTextConfigured { return "Configure Speech to Text in Settings \u{2192} Plugins \u{2192} Speech to Text" }
        return "Start recording"
    }

    var fileAttachmentHelpText: String {
        let base = supportsAudioInput
            ? "Attach images / videos / audio / documents"
            : "Attach images / videos / documents"
        return supportsNativePDF ? "\(base) (native PDF available)" : "\(base) (PDFs may use extraction/OCR)"
    }

    var artifactsHelpText: String {
        if conversationEntity.artifactsEnabled == true {
            return "Artifacts enabled for new replies"
        }
        return "Enable artifact generation for new replies"
    }

    var formattedRecordingDuration: String {
        let total = max(0, Int(speechToTextManager.elapsedSeconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static let supportedAttachmentDocumentExtensions = [
        "docx", "doc", "odt", "rtf",
        "xlsx", "xls", "csv", "tsv",
        "pptx", "ppt",
        "txt", "md", "markdown",
        "json", "html", "htm", "xml"
    ]

    var supportedAttachmentImportTypes: [UTType] {
        var types: [UTType] = []
        var seen: Set<String> = []

        func append(_ type: UTType?) {
            guard let type, seen.insert(type.identifier).inserted else { return }
            types.append(type)
        }

        append(.image)
        append(.movie)
        append(.audio)
        append(.pdf)

        for ext in Self.supportedAttachmentDocumentExtensions {
            append(UTType(filenameExtension: ext))
        }

        return types
    }

    func toggleSpeechToText() {
        Task { @MainActor in
            do {
                if speechToTextManager.isRecording {
                    if speechToTextUsesAudioAttachment {
                        guard draftAttachments.count < AttachmentConstants.maxDraftAttachments else {
                            throw AttachmentImportError(message: "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message.")
                        }

                        let clip = try await speechToTextManager.stopAndCollectRecording()
                        let attachment = try await AttachmentImportPipeline.importRecordedAudioClip(clip)
                        draftAttachments.append(attachment)
                        isComposerFocused = true
                        return
                    }

                    let config = try await currentSpeechToTextTranscriptionConfig()
                    let text = try await speechToTextManager.stopAndTranscribe(config: config)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if messageText.isEmpty {
                            messageText = trimmed
                        } else {
                            let separator = messageText.hasSuffix("\n") ? "\n" : "\n\n"
                            messageText += separator + trimmed
                        }
                        isComposerFocused = true
                    }
                    return
                }

                guard speechToTextPluginEnabled else { return }
                if speechToTextUsesAudioAttachment {
                    guard draftAttachments.count < AttachmentConstants.maxDraftAttachments else {
                        throw AttachmentImportError(message: "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message.")
                    }
                    try await speechToTextManager.startRecording()
                    return
                }

                _ = try await currentSpeechToTextTranscriptionConfig() // Validate configured
                try await speechToTextManager.startRecording()
            } catch {
                speechToTextManager.cancelAndCleanup()
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
