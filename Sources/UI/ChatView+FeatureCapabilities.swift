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
            mineruOCRPluginEnabled: mineruOCRPluginEnabled,
            mineruOCRConfigured: mineruOCRConfigured,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            deepSeekOCRConfigured: deepSeekOCRConfigured,
            openRouterOCRPluginEnabled: openRouterOCRPluginEnabled,
            openRouterOCRConfigured: openRouterOCRConfigured,
            firecrawlOCRPluginEnabled: firecrawlOCRPluginEnabled,
            firecrawlOCRConfigured: firecrawlOCRConfigured
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
            mineruOCRPluginEnabled: mineruOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            openRouterOCRPluginEnabled: openRouterOCRPluginEnabled,
            firecrawlOCRPluginEnabled: firecrawlOCRPluginEnabled
        )
    }

    func resolvedPDFProcessingMode(for controls: GenerationControls, supportsNativePDF: Bool) -> PDFProcessingMode {
        ChatModelCapabilitySupport.resolvedPDFProcessingMode(
            controls: controls,
            supportsNativePDF: supportsNativePDF,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            mineruOCRPluginEnabled: mineruOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            openRouterOCRPluginEnabled: openRouterOCRPluginEnabled,
            firecrawlOCRPluginEnabled: firecrawlOCRPluginEnabled
        )
    }

    var resolvedFirecrawlPDFParserMode: FirecrawlPDFParserMode {
        controls.firecrawlPDFParserMode ?? .ocr
    }

    var pdfProcessingBadgeText: String? {
        ChatModelCapabilitySupport.pdfProcessingBadgeText(mode: resolvedPDFProcessingMode)
    }

    var pdfProcessingHelpText: String {
        ChatModelCapabilitySupport.pdfProcessingHelpText(
            mode: resolvedPDFProcessingMode,
            firecrawlParserMode: resolvedFirecrawlPDFParserMode,
            mistralOCRConfigured: mistralOCRConfigured,
            mineruOCRConfigured: mineruOCRConfigured,
            deepSeekOCRConfigured: deepSeekOCRConfigured,
            openRouterOCRConfigured: openRouterOCRConfigured,
            firecrawlOCRConfigured: firecrawlOCRConfigured
        )
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
        if providerType == .fireworks, isFireworksMiniMaxM2FamilyModel(activeModelID) {
            return true
        }
        return controls.reasoning?.enabled == true
    }

    var supportsReasoningControl: Bool {
        guard !ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType) else { return false }
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
        ChatAuxiliaryControlSupport.isWebSearchEnabled(
            supportsWebSearchControl: supportsWebSearchControl,
            providerType: providerType,
            controls: controls
        )
    }

    var supportsNativeWebSearchControl: Bool {
        ChatAuxiliaryControlSupport.supportsNativeWebSearchControl(
            hidesManagedAgentInternalUI: ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType),
            providerType: providerType,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            supportsImageGenerationControl: supportsImageGenerationControl,
            supportsImageGenerationWebSearch: supportsImageGenerationWebSearch,
            modelSupportsWebSearch: resolvedModelSupportsWebSearch
        )
    }

    var modelSupportsBuiltinSearchPluginControl: Bool {
        ChatAuxiliaryControlSupport.modelSupportsBuiltinSearchPluginControl(
            hidesManagedAgentInternalUI: ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType),
            providerType: providerType,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            modelSupportsToolCalling: resolvedModelSettings?.capabilities.contains(.toolCalling) == true
        )
    }

    var supportsBuiltinSearchPluginControl: Bool {
        ChatAuxiliaryControlSupport.supportsBuiltinSearchPluginControl(
            modelSupportsBuiltinSearchPluginControl: modelSupportsBuiltinSearchPluginControl,
            webSearchPluginEnabled: webSearchPluginEnabled,
            webSearchPluginConfigured: webSearchPluginConfigured
        )
    }

    var supportsSearchEngineModeSwitch: Bool {
        ChatAuxiliaryControlSupport.supportsSearchEngineModeSwitch(
            supportsNativeWebSearchControl: supportsNativeWebSearchControl,
            supportsBuiltinSearchPluginControl: supportsBuiltinSearchPluginControl
        )
    }

    var prefersJinSearchEngine: Bool {
        controls.searchPlugin?.preferJinSearch == true
    }

    var usesBuiltinSearchPlugin: Bool {
        ChatAuxiliaryControlSupport.usesBuiltinSearchPlugin(
            supportsNativeWebSearchControl: supportsNativeWebSearchControl,
            supportsBuiltinSearchPluginControl: supportsBuiltinSearchPluginControl,
            prefersJinSearchEngine: prefersJinSearchEngine
        )
    }

    var modelSupportsWebSearchControl: Bool {
        ChatAuxiliaryControlSupport.modelSupportsWebSearchControl(
            supportsNativeWebSearchControl: supportsNativeWebSearchControl,
            modelSupportsBuiltinSearchPluginControl: modelSupportsBuiltinSearchPluginControl
        )
    }

    var supportsWebSearchControl: Bool {
        ChatAuxiliaryControlSupport.supportsWebSearchControl(
            supportsNativeWebSearchControl: supportsNativeWebSearchControl,
            supportsBuiltinSearchPluginControl: supportsBuiltinSearchPluginControl
        )
    }

    var resolvedModelSupportsWebSearch: Bool {
        if let resolvedModelSettings {
            return resolvedModelSettings.supportsWebSearch
        }

        return ModelCapabilityRegistry.supportsWebSearch(
            for: providerType,
            modelID: activeModelID
        )
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
        CodeExecutionSheetSupport.supportsConfiguration(for: providerType)
    }

    var codeExecutionEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.codeExecution?.enabled ?? false },
            set: { enabled in
                controls = ChatAuxiliaryControlSupport.setCodeExecutionEnabled(
                    enabled,
                    controls: controls
                )
                persistControlsToConversation()
            }
        )
    }

    var isCodeExecutionDraftValid: Bool {
        CodeExecutionSheetSupport.isDraftValid(
            providerType: providerType,
            openAIUseExistingContainer: codeExecutionOpenAIUseExistingContainer,
            openAI: codeExecutionDraft.openAI
        )
    }

    var parsedCodeExecutionOpenAIFileIDsDraft: [String] {
        CodeExecutionSheetSupport.parsedOpenAIFileIDsDraft(codeExecutionOpenAIFileIDsDraft)
    }

    var codeExecutionBadgeText: String? {
        CodeExecutionSheetSupport.badgeText(
            isEnabled: isCodeExecutionEnabled,
            providerType: providerType,
            controls: controls.codeExecution
        )
    }

    var codeExecutionHelpText: String {
        CodeExecutionSheetSupport.helpText(
            isEnabled: isCodeExecutionEnabled,
            providerType: providerType,
            controls: controls.codeExecution
        )
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
        ChatModelCapabilitySupport.googleMapsBadgeText(
            isEnabled: isGoogleMapsEnabled,
            hasLocation: controls.googleMaps?.hasLocation == true
        )
    }

    var googleMapsHelpText: String {
        ChatModelCapabilitySupport.googleMapsHelpText(
            isEnabled: isGoogleMapsEnabled,
            hasLocation: controls.googleMaps?.hasLocation == true
        )
    }

    var googleMapsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.googleMaps?.enabled == true },
            set: { enabled in
                controls = ChatAuxiliaryControlSupport.setGoogleMapsEnabled(enabled, controls: controls)
                persistControlsToConversation()
            }
        )
    }

    // MARK: - MCP Tools

    var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled == true
    }

    var supportsMCPToolsControl: Bool {
        ChatMCPToolCapabilitySupport.supportsMCPTools(
            providerType: providerType,
            resolvedModelSettings: resolvedModelSettings
        )
    }

    var eligibleMCPServers: [MCPServerConfigEntity] {
        ChatAuxiliaryControlSupport.eligibleMCPServers(from: mcpServers)
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
