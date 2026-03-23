import SwiftUI

// MARK: - Feature Capabilities: PDF, Reasoning, Web Search, Code Execution, Google Maps, MCP

extension ChatView {

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
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .gemini, .vertexai, .morphllm, .opencodeGo, .none:
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
}
