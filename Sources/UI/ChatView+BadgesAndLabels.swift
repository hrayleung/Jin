import SwiftUI

// MARK: - Help Text, Labels, Badge Text & PDF Processing Menu

extension ChatView {

    // MARK: - Help Text & Labels

    var reasoningHelpText: String {
        ChatReasoningSupport.reasoningHelpText(
            supportsReasoningControl: supportsReasoningControl,
            providerType: providerType,
            label: reasoningLabel
        )
    }

    var webSearchHelpText: String {
        ChatAuxiliaryControlSupport.webSearchHelpText(
            supportsWebSearchControl: supportsWebSearchControl,
            isWebSearchEnabled: isWebSearchEnabled,
            label: webSearchLabel
        )
    }

    var openAIServiceTierHelpText: String {
        ChatAuxiliaryControlSupport.openAIServiceTierHelpText(
            supportsOpenAIServiceTierControl: supportsOpenAIServiceTierControl,
            label: openAIServiceTierLabel
        )
    }

    var anthropicFastModeHelpText: String {
        ChatAuxiliaryControlSupport.anthropicFastModeHelpText(
            supportsAnthropicFastModeControl: supportsAnthropicFastModeControl,
            controls: controls
        )
    }

    var mcpToolsHelpText: String {
        ChatAuxiliaryControlSupport.mcpToolsHelpText(
            supportsMCPToolsControl: supportsMCPToolsControl,
            isMCPToolsEnabled: isMCPToolsEnabled,
            selectedServerCount: selectedMCPServerIDs.count
        )
    }

    var claudeManagedAgentSessionHelpText: String {
        let resolvedControls = resolvedClaudeManagedControls(
            for: activeProviderID,
            threadControls: controls
        )

        let agentDisplayName = resolvedControls.claudeManagedAgentID.map { _ in
            resolvedClaudeManagedAgentDisplayName(
                for: activeProviderID,
                modelID: activeModelID,
                controls: controls
            )
        }

        let environmentDisplayName = resolvedControls.claudeManagedEnvironmentID.flatMap { _ in
            resolvedClaudeManagedEnvironmentDisplayName(
                for: activeProviderID,
                threadControls: controls
            )
        }

        return ChatAuxiliaryControlSupport.claudeManagedAgentSessionHelpText(
            supportsClaudeManagedAgentSessionControl: supportsClaudeManagedAgentSessionControl,
            resolvedControls: resolvedControls,
            agentDisplayName: agentDisplayName,
            environmentDisplayName: environmentDisplayName
        )
    }

    var webSearchLabel: String {
        ChatAuxiliaryControlSupport.webSearchLabel(
            providerType: providerType,
            controls: controls,
            usesBuiltinSearchPlugin: usesBuiltinSearchPlugin,
            searchPluginProvider: effectiveSearchPluginProvider
        )
    }

    var openAIServiceTierLabel: String {
        ChatAuxiliaryControlSupport.openAIServiceTierLabel(controls: controls)
    }

    var webSearchSourcesLabel: String {
        ChatAuxiliaryControlSupport.webSearchSourcesLabel(controls: controls)
    }

    // MARK: - Badge Text

    var reasoningBadgeText: String? {
        ChatReasoningSupport.reasoningBadgeText(
            supportsReasoningControl: supportsReasoningControl,
            isReasoningEnabled: isReasoningEnabled,
            selectedReasoningConfig: selectedReasoningConfig,
            controls: controls
        )
    }

    var openAIServiceTierBadgeText: String? {
        ChatAuxiliaryControlSupport.openAIServiceTierBadgeText(
            supportsOpenAIServiceTierControl: supportsOpenAIServiceTierControl,
            controls: controls
        )
    }

    var anthropicFastModeBadgeText: String? {
        ChatAuxiliaryControlSupport.anthropicFastModeBadgeText(
            supportsAnthropicFastModeControl: supportsAnthropicFastModeControl,
            controls: controls
        )
    }

    var webSearchBadgeText: String? {
        ChatAuxiliaryControlSupport.webSearchBadgeText(
            supportsWebSearchControl: supportsWebSearchControl,
            isWebSearchEnabled: isWebSearchEnabled,
            providerType: providerType,
            controls: controls,
            usesBuiltinSearchPlugin: usesBuiltinSearchPlugin,
            searchPluginProvider: effectiveSearchPluginProvider
        )
    }

    var mcpToolsBadgeText: String? {
        ChatAuxiliaryControlSupport.mcpToolsBadgeText(
            supportsMCPToolsControl: supportsMCPToolsControl,
            isMCPToolsEnabled: isMCPToolsEnabled,
            selectedServerCount: selectedMCPServerIDs.count
        )
    }

    // MARK: - PDF Processing Menu

    func setPDFProcessingMode(_ mode: PDFProcessingMode) {
        guard isPDFProcessingModeAvailable(mode) else { return }
        controls = ChatModelCapabilitySupport.setPDFProcessingMode(
            mode,
            controls: controls
        )
        persistControlsToConversation()
    }

    func setFirecrawlPDFParserMode(_ mode: FirecrawlPDFParserMode) {
        controls = ChatModelCapabilitySupport.setFirecrawlPDFParserMode(
            mode,
            controls: controls
        )
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

        if mineruOCRPluginEnabled {
            Button { setPDFProcessingMode(.mineruOCR) } label: { menuItemLabel("MinerU OCR", isSelected: resolvedPDFProcessingMode == .mineruOCR) }
        }

        if deepSeekOCRPluginEnabled {
            Button { setPDFProcessingMode(.deepSeekOCR) } label: { menuItemLabel("DeepSeek OCR (DeepInfra)", isSelected: resolvedPDFProcessingMode == .deepSeekOCR) }
        }

        if openRouterOCRPluginEnabled {
            Button { setPDFProcessingMode(.openRouterOCR) } label: { menuItemLabel("OpenRouter OCR", isSelected: resolvedPDFProcessingMode == .openRouterOCR) }
        }

        if firecrawlOCRPluginEnabled {
            Button { setPDFProcessingMode(.firecrawlOCR) } label: { menuItemLabel("Firecrawl OCR", isSelected: resolvedPDFProcessingMode == .firecrawlOCR) }
        }

        Button { setPDFProcessingMode(.macOSExtract) } label: { menuItemLabel("macOS Extract", isSelected: resolvedPDFProcessingMode == .macOSExtract) }

        if resolvedPDFProcessingMode == .mistralOCR, !mistralOCRConfigured {
            Divider()
            Text("Set API key in Settings \u{2192} Plugins \u{2192} Mistral OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if resolvedPDFProcessingMode == .mineruOCR, !mineruOCRConfigured {
            Divider()
            Text("Set API token in Settings \u{2192} Plugins \u{2192} MinerU OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if resolvedPDFProcessingMode == .deepSeekOCR, !deepSeekOCRConfigured {
            Divider()
            Text("Set API key in Settings \u{2192} Plugins \u{2192} DeepSeek OCR (DeepInfra).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if resolvedPDFProcessingMode == .openRouterOCR, !openRouterOCRConfigured {
            Divider()
            Text("Set API key in Settings \u{2192} Plugins \u{2192} OpenRouter OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if resolvedPDFProcessingMode == .firecrawlOCR {
            Divider()
            Menu {
                ForEach(FirecrawlPDFParserMode.allCases, id: \.rawValue) { mode in
                    Button { setFirecrawlPDFParserMode(mode) } label: {
                        menuItemLabel(mode.displayName, isSelected: resolvedFirecrawlPDFParserMode == mode)
                    }
                }
            } label: {
                Text("Firecrawl parser mode: \(resolvedFirecrawlPDFParserMode.displayName)")
            }

            if !firecrawlOCRConfigured {
                Text("Set the Firecrawl API key in Settings \u{2192} Plugins \u{2192} Firecrawl OCR, then configure Cloudflare R2 Upload for temporary PDF hosting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !mistralOCRPluginEnabled && !mineruOCRPluginEnabled && !deepSeekOCRPluginEnabled && !openRouterOCRPluginEnabled && !firecrawlOCRPluginEnabled {
            Divider()
            Text("OCR plugins are turned off. Enable Mistral OCR, MinerU OCR, DeepSeek OCR, OpenRouter OCR, or Firecrawl OCR in Settings \u{2192} Plugins to show OCR modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
