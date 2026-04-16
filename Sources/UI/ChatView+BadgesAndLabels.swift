import SwiftUI

// MARK: - Help Text, Labels, Badge Text & PDF Processing Menu

extension ChatView {

    // MARK: - Help Text & Labels

    var reasoningHelpText: String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .claudeManagedAgents, .gemini, .vertexai:
            return "Thinking: \(reasoningLabel)"
        case .perplexity:
            return "Reasoning: \(reasoningLabel)"
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
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

    var claudeManagedAgentSessionHelpText: String {
        guard supportsClaudeManagedAgentSessionControl else { return "Claude Managed Agent: Not supported" }

        var segments: [String] = []
        let resolvedControls = resolvedClaudeManagedControls(
            for: conversationEntity.providerID,
            threadControls: controls
        )

        if resolvedControls.claudeManagedAgentID != nil {
            let label = resolvedClaudeManagedAgentDisplayName(
                for: conversationEntity.providerID,
                threadModelID: conversationEntity.modelID,
                threadControls: controls
            )
            segments.append("Agent: \(label)")
        } else {
            segments.append("Agent: not configured")
        }

        if resolvedControls.claudeManagedEnvironmentID != nil,
           let label = resolvedClaudeManagedEnvironmentDisplayName(
                for: conversationEntity.providerID,
                threadControls: controls
           ) {
            segments.append("Environment: \(label)")
        } else {
            segments.append("Environment: not configured")
        }

        if let sessionID = resolvedControls.claudeManagedSessionID {
            segments.append("Session: \(sessionID)")
        }

        return "Claude Managed Agent: " + segments.joined(separator: " \u{00B7} ")
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
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .anthropic, .claudeManagedAgents,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
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
            case .max: return "Max"
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
        case .anthropic, .claudeManagedAgents:
            return "On"
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
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

    func setFirecrawlPDFParserMode(_ mode: FirecrawlPDFParserMode) {
        controls.firecrawlPDFParserMode = (mode == .ocr) ? nil : mode
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

        if !mistralOCRPluginEnabled && !mineruOCRPluginEnabled && !deepSeekOCRPluginEnabled && !firecrawlOCRPluginEnabled {
            Divider()
            Text("OCR plugins are turned off. Enable Mistral OCR, MinerU OCR, DeepSeek OCR, or Firecrawl OCR in Settings \u{2192} Plugins to show OCR modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
