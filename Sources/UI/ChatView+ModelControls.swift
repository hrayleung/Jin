import SwiftUI
import SwiftData

// MARK: - Model Controls

extension ChatView {

    
    var providerType: ProviderType? {
        if let provider = providers.first(where: { $0.id == conversationEntity.providerID }),
           let providerType = ProviderType(rawValue: provider.typeRaw) {
            return providerType
        }

        // Fallback: for the built-in providers, `providerID` matches the provider type.
        return ProviderType(rawValue: conversationEntity.providerID)
    }

    var reasoningLabel: String {
        guard supportsReasoningControl else { return "Not supported" }
        guard isReasoningEnabled else { return "Off" }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return "Not supported" }

        switch reasoningType {
        case .budget:
            guard let budgetTokens = controls.reasoning?.budgetTokens else { return "On" }
            return "\(budgetTokens) tokens"
        case .effort:
            if providerType == .anthropic {
                if anthropicUsesEffortMode {
                    let effort = controls.reasoning?.effort ?? selectedReasoningConfig?.defaultEffort ?? .high
                    return effort == .xhigh ? "Max" : effort.displayName
                }
                let budgetTokens = controls.reasoning?.budgetTokens ?? anthropicDefaultBudgetTokens
                return "\(budgetTokens) tokens"
            }
            return controls.reasoning?.effort?.displayName ?? "On"
        case .toggle:
            return "On"
        case .none:
            return "Not supported"
        }
    }

    var supportsReasoningSummaryControl: Bool {
        providerType == .openai || providerType == .openaiWebSocket || providerType == .codexAppServer
    }

    @ViewBuilder
    var reasoningMenuContent: some View {
        ReasoningControlMenuView(
            reasoningConfig: selectedReasoningConfig,
            supportsReasoningDisableToggle: supportsReasoningDisableToggle,
            isReasoningEnabled: isReasoningEnabled,
            isAnthropicProvider: providerType == .anthropic,
            supportsCerebrasPreservedThinkingToggle: supportsCerebrasPreservedThinkingToggle,
            cerebrasPreserveThinkingBinding: cerebrasPreserveThinkingBinding,
            availableReasoningEffortLevels: availableReasoningEffortLevels,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl,
            currentReasoningSummary: controls.reasoning?.summary ?? .auto,
            currentReasoningEffort: controls.reasoning?.effort,
            supportsFireworksReasoningHistoryToggle: supportsFireworksReasoningHistoryToggle,
            fireworksReasoningHistoryOptions: fireworksReasoningHistoryOptions,
            fireworksReasoningHistory: fireworksReasoningHistory,
            budgetTokensLabel: String(controls.reasoning?.budgetTokens ?? selectedReasoningConfig?.defaultBudget ?? 1024),
            fireworksReasoningHistoryLabel: { option in
                fireworksReasoningHistoryLabel(for: option)
            },
            menuItemLabel: { title, isSelected in
                menuItemLabel(title, isSelected: isSelected)
            },
            onSetReasoningOff: {
                setReasoningOff()
            },
            onSetReasoningOn: {
                setReasoningOn()
            },
            onOpenThinkingBudgetEditor: {
                openThinkingBudgetEditor()
            },
            onSetReasoningEffort: { effort in
                setReasoningEffort(effort)
            },
            onSetReasoningSummary: { summary in
                setReasoningSummary(summary)
            },
            onSetFireworksReasoningHistory: { value in
                setFireworksReasoningHistory(value)
            }
        )
    }

    @ViewBuilder
    var openAIServiceTierMenuContent: some View {
        Button { setOpenAIServiceTier(nil) } label: {
            menuItemLabel("Auto (OpenAI default)", isSelected: controls.openAIServiceTier == nil)
        }

        Divider()

        ForEach(OpenAIServiceTier.allCases, id: \.self) { serviceTier in
            Button {
                setOpenAIServiceTier(serviceTier)
            } label: {
                menuItemLabel(serviceTier.displayName, isSelected: controls.openAIServiceTier == serviceTier)
            }
        }
    }

    @ViewBuilder
    var googleMapsMenuContent: some View {
        Toggle("Google Maps", isOn: googleMapsEnabledBinding)

        Divider()

        Button("Configure Location…") {
            openGoogleMapsSheet()
        }

        if isGoogleMapsEnabled, controls.googleMaps?.hasLocation == true {
            Divider()
            Button("Clear Location") {
                controls.googleMaps?.latitude = nil
                controls.googleMaps?.longitude = nil
                persistControlsToConversation()
            }
        }
    }

    func openGoogleMapsSheet() {
        let prepared = ChatAuxiliaryControlSupport.prepareGoogleMapsEditorDraft(
            current: controls.googleMaps,
            isEnabled: isGoogleMapsEnabled
        )
        googleMapsDraft = prepared.draft
        googleMapsLatitudeDraft = prepared.latitudeDraft
        googleMapsLongitudeDraft = prepared.longitudeDraft
        googleMapsLanguageCodeDraft = prepared.languageCodeDraft
        googleMapsDraftError = nil
        showingGoogleMapsSheet = true
    }

    var isGoogleMapsDraftValid: Bool {
        ChatAuxiliaryControlSupport.isGoogleMapsDraftValid(
            latitudeDraft: googleMapsLatitudeDraft,
            longitudeDraft: googleMapsLongitudeDraft
        )
    }

    @discardableResult
    func applyGoogleMapsDraft() -> Bool {
        switch ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
            draft: googleMapsDraft,
            latitudeDraft: googleMapsLatitudeDraft,
            longitudeDraft: googleMapsLongitudeDraft,
            languageCodeDraft: googleMapsLanguageCodeDraft,
            providerType: providerType
        ) {
        case .success(let draft):
            controls.googleMaps = draft
            googleMapsDraftError = nil
            persistControlsToConversation()
            return true
        case .failure(let error):
            googleMapsDraftError = error.localizedDescription
            return false
        }
    }

    @ViewBuilder
    var codeExecutionMenuContent: some View {
        Toggle("Code Execution", isOn: codeExecutionEnabledBinding)

        Divider()

        Button("Configure…") {
            openCodeExecutionSheet()
        }

        if providerType == .vertexai {
            Divider()
            Text("Vertex AI code execution doesn't support file I/O.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func openCodeExecutionSheet() {
        codeExecutionDraftError = nil
        codeExecutionDraft = controls.codeExecution ?? CodeExecutionControls(enabled: isCodeExecutionEnabled)

        let openAISettings = codeExecutionDraft.openAI?.normalized()
        codeExecutionOpenAIUseExistingContainer = openAISettings?.normalizedExistingContainerID != nil
        codeExecutionOpenAIFileIDsDraft = openAISettings?.container?.normalizedFileIDs?.joined(separator: "\n") ?? ""

        if providerType == .openai,
           !codeExecutionOpenAIUseExistingContainer,
           codeExecutionDraft.openAI == nil {
            codeExecutionDraft.openAI = OpenAICodeExecutionOptions(
                container: CodeExecutionContainer(type: "auto")
            )
        }

        showingCodeExecutionSheet = true
    }

    @discardableResult
    func applyCodeExecutionDraft() -> Bool {
        codeExecutionDraftError = nil

        if providerType == .openai {
            var openAI = codeExecutionDraft.openAI ?? OpenAICodeExecutionOptions()

            if codeExecutionOpenAIUseExistingContainer {
                guard let existingContainerID = openAI.normalizedExistingContainerID else {
                    codeExecutionDraftError = "Enter an OpenAI container ID."
                    return false
                }
                openAI.existingContainerID = existingContainerID
                openAI.container = nil
            } else {
                var container = openAI.container ?? CodeExecutionContainer(type: "auto")
                container.type = "auto"
                container.fileIDs = parsedCodeExecutionOpenAIFileIDsDraft
                openAI.container = container.normalized()
                openAI.existingContainerID = nil
            }

            codeExecutionDraft.openAI = openAI.normalized()
        }

        if providerType == .anthropic {
            codeExecutionDraft.anthropic = codeExecutionDraft.anthropic?.normalized()
        }

        controls.codeExecution = codeExecutionDraft
        persistControlsToConversation()
        return true
    }

    func setOpenAIServiceTier(_ serviceTier: OpenAIServiceTier?) {
        controls.openAIServiceTier = serviceTier
        persistControlsToConversation()
    }

    var supportsFireworksReasoningHistoryToggle: Bool {
        !fireworksReasoningHistoryOptions.isEmpty
    }

    var fireworksReasoningHistoryOptions: [String] {
        guard providerType == .fireworks else { return [] }
        if isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return ["interleaved", "disabled"]
        }
        if isFireworksModelID(conversationEntity.modelID, canonicalID: "kimi-k2p5")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-4p7")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-5") {
            return ["preserved", "interleaved", "disabled"]
        }
        return []
    }

    var fireworksReasoningHistory: String? {
        controls.providerSpecific["reasoning_history"]?.value as? String
    }

    func setFireworksReasoningHistory(_ value: String?) {
        if let value {
            controls.providerSpecific["reasoning_history"] = AnyCodable(value)
        } else {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
        persistControlsToConversation()
    }

    func isFireworksModelID(_ modelID: String, canonicalID: String) -> Bool {
        fireworksCanonicalModelID(modelID) == canonicalID
    }

    func fireworksReasoningHistoryLabel(for option: String) -> String {
        switch option {
        case "preserved":
            return "Preserved"
        case "interleaved":
            return "Interleaved"
        case "disabled":
            return "Disabled"
        default:
            return option
        }
    }

    var supportsCerebrasPreservedThinkingToggle: Bool {
        guard providerType == .cerebras else { return false }
        return conversationEntity.modelID.lowercased() == "zai-glm-4.7"
    }

    var cerebrasPreserveThinkingBinding: Binding<Bool> {
        Binding(
            get: {
                // Cerebras `clear_thinking` defaults to true. Preserve thinking == clear_thinking false.
                let clear = (controls.providerSpecific["clear_thinking"]?.value as? Bool) ?? true
                return clear == false
            },
            set: { preserve in
                if preserve {
                    controls.providerSpecific["clear_thinking"] = AnyCodable(false)
                } else {
                    // Use provider default (clear_thinking true).
                    controls.providerSpecific.removeValue(forKey: "clear_thinking")
                }
                persistControlsToConversation()
            }
        )
    }

    func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .fixedSize()
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    @ViewBuilder
    func effortLevelButtons(for levels: [ReasoningEffort]) -> some View {
        ForEach(levels, id: \.self) { level in
            Button { setReasoningEffort(level) } label: {
                menuItemLabel(
                    level == .xhigh ? "Extreme" : level.displayName,
                    isSelected: isReasoningEnabled && controls.reasoning?.effort == level
                )
            }
        }
    }

    var webSearchEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                if providerType == .perplexity {
                    return controls.webSearch?.enabled ?? true
                }
                return controls.webSearch?.enabled ?? false
            },
            set: { enabled in
                if controls.webSearch == nil {
                    controls.webSearch = defaultWebSearchControls(enabled: enabled)
                } else {
                    controls.webSearch?.enabled = enabled
                    ensureValidWebSearchDefaultsIfEnabled()
                }
                persistControlsToConversation()
            }
        )
    }

    var anthropicDynamicFilteringBinding: Binding<Bool> {
        Binding(
            get: { controls.webSearch?.dynamicFiltering ?? false },
            set: { newValue in
                controls.webSearch?.dynamicFiltering = newValue ? true : nil
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    var webSearchMenuContent: some View {
        WebSearchControlMenuView(
            isEnabled: webSearchEnabledBinding,
            isWebSearchEnabled: isWebSearchEnabled,
            supportsSearchEngineModeSwitch: supportsSearchEngineModeSwitch,
            usesBuiltinSearchPlugin: usesBuiltinSearchPlugin,
            effectiveSearchPluginProvider: effectiveSearchPluginProvider,
            builtinMaxResults: controls.searchPlugin?.maxResults ?? WebSearchPluginSettingsStore.load().defaultMaxResults,
            builtinRecencyDays: controls.searchPlugin?.recencyDays,
            providerType: providerType,
            openAIContextSize: controls.webSearch?.contextSize ?? .medium,
            perplexityContextSize: controls.webSearch?.contextSize ?? .low,
            xaiSourcesAreEmpty: Set(controls.webSearch?.sources ?? []).isEmpty,
            anthropicMaxUses: controls.webSearch?.maxUses,
            supportsAnthropicDynamicFiltering: supportsAnthropicDynamicFiltering,
            builtinSearchIncludeRawBinding: builtinSearchIncludeRawBinding,
            builtinSearchFetchPageBinding: builtinSearchFetchPageBinding,
            builtinSearchFirecrawlExtractBinding: builtinSearchFirecrawlExtractBinding,
            xaiWebBinding: webSearchSourceBinding(.web),
            xaiXBinding: webSearchSourceBinding(.x),
            anthropicDynamicFilteringBinding: anthropicDynamicFilteringBinding,
            menuItemLabel: { title, isSelected in
                menuItemLabel(title, isSelected: isSelected)
            },
            onSetSearchEnginePreference: { useJinSearch in
                setSearchEnginePreference(useJinSearch: useJinSearch)
            },
            onSelectSearchProvider: { provider in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.provider = provider
                persistControlsToConversation()
            },
            onSelectBuiltinMaxResults: { value in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.maxResults = value
                persistControlsToConversation()
            },
            onSelectBuiltinRecencyDays: { value in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.recencyDays = value
                persistControlsToConversation()
            },
            onSelectOpenAIContextSize: { size in
                controls.webSearch?.contextSize = size
                persistControlsToConversation()
            },
            onSelectPerplexityContextSize: { size in
                if controls.webSearch == nil {
                    controls.webSearch = defaultWebSearchControls(enabled: true)
                }
                controls.webSearch?.contextSize = size
                persistControlsToConversation()
            },
            onSelectAnthropicMaxUses: { value in
                controls.webSearch?.maxUses = value
                persistControlsToConversation()
            },
            onOpenAnthropicConfiguration: {
                openAnthropicWebSearchEditor()
            }
        )
    }

    func setSearchEnginePreference(useJinSearch: Bool) {
        if controls.searchPlugin == nil {
            controls.searchPlugin = SearchPluginControls()
        }
        controls.searchPlugin?.preferJinSearch = useJinSearch
        persistControlsToConversation()
    }

    @ViewBuilder
    var contextCacheMenuContent: some View {
        ContextCacheControlMenuView(
            effectiveMode: effectiveContextCacheMode,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode,
            showsReset: controls.contextCache != nil,
            onTurnOff: {
                controls.contextCache = ContextCacheControls(mode: .off)
                persistControlsToConversation()
            },
            onSetImplicit: {
                var cache = controls.contextCache ?? ContextCacheControls(mode: .implicit)
                cache.mode = .implicit
                if providerType != .anthropic {
                    cache.strategy = nil
                }
                if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
                    cache.cacheKey = nil
                }
                if providerType != .xai {
                    cache.minTokensThreshold = nil
                }
                if providerType != .xai {
                    cache.conversationID = nil
                }
                if providerType != .gemini && providerType != .vertexai {
                    cache.cachedContentName = nil
                }
                controls.contextCache = cache
                persistControlsToConversation()
            },
            onSetExplicit: {
                var cache = controls.contextCache ?? ContextCacheControls(mode: .explicit)
                cache.mode = .explicit
                controls.contextCache = cache
                persistControlsToConversation()
            },
            onConfigure: {
                openContextCacheEditor()
            },
            onReset: {
                controls.contextCache = nil
                persistControlsToConversation()
            },
            menuItemLabel: { title, isSelected in
                menuItemLabel(title, isSelected: isSelected)
            }
        )
    }

    var mcpToolsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.mcpTools?.enabled == true },
            set: { enabled in
                if controls.mcpTools == nil {
                    controls.mcpTools = MCPToolsControls(enabled: enabled)
                } else {
                    controls.mcpTools?.enabled = enabled
                }
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    var mcpToolsMenuContent: some View {
        MCPToolsControlMenuView(
            isEnabled: mcpToolsEnabledBinding,
            isMCPToolsEnabled: isMCPToolsEnabled,
            servers: mcpServerMenuItems,
            selectedServerIDs: selectedMCPServerIDs,
            usesCustomServerSelection: controls.mcpTools?.enabledServerIDs != nil,
            onUseAllServers: {
                resetMCPServerSelection()
            }
        )
    }

    @ViewBuilder
    var imageGenerationMenuContent: some View {
        if providerType == .xai {
            XAIImageGenerationMenuView(
                isConfigured: isImageGenerationConfigured,
                currentCount: controls.xaiImageGeneration?.count,
                selectedAspectRatio: controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio,
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetCount: { value in
                    updateXAIImageGeneration { $0.count = value }
                },
                onSetAspectRatio: { value in
                    if let value {
                        updateXAIImageGeneration {
                            $0.aspectRatio = value
                            $0.size = nil
                        }
                    } else {
                        updateXAIImageGeneration {
                            $0.aspectRatio = nil
                            $0.size = nil
                        }
                    }
                },
                onReset: {
                    controls.xaiImageGeneration = nil
                    persistControlsToConversation()
                }
            )
        } else if providerType == .openai || providerType == .openaiWebSocket {
            OpenAIImageGenerationMenuView(
                isConfigured: isImageGenerationConfigured,
                isGPTImageModel: lowerModelID.hasPrefix("gpt-image"),
                isDallE3: lowerModelID.hasPrefix("dall-e-3"),
                showsInputFidelity: lowerModelID == "gpt-image-1",
                currentCount: controls.openaiImageGeneration?.count,
                currentSize: controls.openaiImageGeneration?.size,
                currentQuality: controls.openaiImageGeneration?.quality,
                currentStyle: controls.openaiImageGeneration?.style,
                currentBackground: controls.openaiImageGeneration?.background,
                currentOutputFormat: controls.openaiImageGeneration?.outputFormat,
                currentOutputCompression: controls.openaiImageGeneration?.outputCompression,
                currentModeration: controls.openaiImageGeneration?.moderation,
                currentInputFidelity: controls.openaiImageGeneration?.inputFidelity,
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetCount: { value in
                    updateOpenAIImageGeneration { $0.count = value }
                },
                onSetSize: { value in
                    updateOpenAIImageGeneration { $0.size = value }
                },
                onSetQuality: { value in
                    updateOpenAIImageGeneration { $0.quality = value }
                },
                onSetStyle: { value in
                    updateOpenAIImageGeneration { $0.style = value }
                },
                onSetBackground: { value in
                    updateOpenAIImageGeneration { $0.background = value }
                },
                onSetOutputFormat: { value in
                    updateOpenAIImageGeneration { $0.outputFormat = value }
                },
                onSetOutputCompression: { value in
                    updateOpenAIImageGeneration { $0.outputCompression = value }
                },
                onSetModeration: { value in
                    updateOpenAIImageGeneration { $0.moderation = value }
                },
                onSetInputFidelity: { value in
                    updateOpenAIImageGeneration { $0.inputFidelity = value }
                },
                onReset: {
                    controls.openaiImageGeneration = nil
                    persistControlsToConversation()
                }
            )
        } else {
            Button("Edit…") {
                openImageGenerationEditor()
            }

            if isImageGenerationConfigured {
                Divider()
                Button("Reset", role: .destructive) {
                    controls.imageGeneration = nil
                    persistControlsToConversation()
                }
            }
        }
    }

    func updateOpenAIImageGeneration(_ mutate: (inout OpenAIImageGenerationControls) -> Void) {
        var draft = controls.openaiImageGeneration ?? OpenAIImageGenerationControls()
        mutate(&draft)

        // If background is transparent, ensure output format supports transparency
        if draft.background == .transparent {
            if let format = draft.outputFormat, format == .jpeg {
                draft.outputFormat = .png
            }
        }

        // Clear compression if format doesn't support it
        if let format = draft.outputFormat, format == .png {
            draft.outputCompression = nil
        }
        if draft.outputFormat == nil {
            draft.outputCompression = nil
        }

        controls.openaiImageGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func updateXAIImageGeneration(_ mutate: (inout XAIImageGenerationControls) -> Void) {
        var draft = controls.xaiImageGeneration ?? XAIImageGenerationControls()
        mutate(&draft)

        // These legacy fields are not supported by current xAI image APIs.
        draft.quality = nil
        draft.style = nil
        if draft.aspectRatio != nil {
            draft.size = nil
        }

        controls.xaiImageGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    @ViewBuilder
    var videoGenerationMenuContent: some View {
        switch providerType {
        case .gemini, .vertexai:
            GoogleVideoGenerationMenuView(
                isVeo3: GoogleVideoGenerationCore.isVeo3OrLater(conversationEntity.modelID),
                isVertexProvider: providerType == .vertexai,
                isConfigured: isVideoGenerationConfigured,
                currentDurationSeconds: controls.googleVideoGeneration?.durationSeconds,
                currentAspectRatio: controls.googleVideoGeneration?.aspectRatio,
                currentResolution: controls.googleVideoGeneration?.resolution,
                currentPersonGeneration: controls.googleVideoGeneration?.personGeneration,
                generateAudioBinding: Binding(
                    get: { controls.googleVideoGeneration?.generateAudio ?? false },
                    set: { newValue in
                        updateGoogleVideoGeneration { $0.generateAudio = newValue ? true : nil }
                    }
                ),
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetDurationSeconds: { value in
                    updateGoogleVideoGeneration { $0.durationSeconds = value }
                },
                onSetAspectRatio: { value in
                    updateGoogleVideoGeneration { $0.aspectRatio = value }
                },
                onSetResolution: { value in
                    updateGoogleVideoGeneration { $0.resolution = value }
                },
                onSetPersonGeneration: { value in
                    updateGoogleVideoGeneration { $0.personGeneration = value }
                },
                onReset: {
                    controls.googleVideoGeneration = nil
                    persistControlsToConversation()
                }
            )
        case .xai:
            XAIVideoGenerationMenuView(
                isConfigured: isVideoGenerationConfigured,
                currentDuration: controls.xaiVideoGeneration?.duration,
                currentAspectRatio: controls.xaiVideoGeneration?.aspectRatio,
                currentResolution: controls.xaiVideoGeneration?.resolution,
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetDuration: { value in
                    updateXAIVideoGeneration { $0.duration = value }
                },
                onSetAspectRatio: { value in
                    updateXAIVideoGeneration { $0.aspectRatio = value }
                },
                onSetResolution: { value in
                    updateXAIVideoGeneration { $0.resolution = value }
                },
                onReset: {
                    controls.xaiVideoGeneration = nil
                    persistControlsToConversation()
                }
            )
        default:
            EmptyView()
        }
    }

    func updateXAIVideoGeneration(_ mutate: (inout XAIVideoGenerationControls) -> Void) {
        var draft = controls.xaiVideoGeneration ?? XAIVideoGenerationControls()
        mutate(&draft)
        controls.xaiVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func updateGoogleVideoGeneration(_ mutate: (inout GoogleVideoGenerationControls) -> Void) {
        var draft = controls.googleVideoGeneration ?? GoogleVideoGenerationControls()
        mutate(&draft)
        controls.googleVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func openImageGenerationEditor() {
        let prepared = ChatEditorDraftSupport.prepareImageGenerationEditorDraft(
            current: controls.imageGeneration,
            supportedAspectRatios: supportedCurrentModelImageAspectRatios,
            supportedImageSizes: supportedCurrentModelImageSizes
        )
        imageGenerationDraft = prepared.draft
        imageGenerationSeedDraft = prepared.seedDraft
        imageGenerationCompressionQualityDraft = prepared.compressionQualityDraft
        imageGenerationDraftError = nil
        showingImageGenerationSheet = true
    }

    func openCodexSessionSettingsEditor() {
        codexWorkingDirectoryDraft = codexWorkingDirectory ?? ""
        codexWorkingDirectoryDraftError = nil
        codexSandboxModeDraft = controls.codexSandboxMode
        codexPersonalityDraft = controls.codexPersonality
        showingCodexSessionSettingsSheet = true
    }

    func pickCodexWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = "Choose a working directory to send as Codex `cwd`."

        if let existing = normalizedCodexWorkingDirectoryPath(from: codexWorkingDirectoryDraft) {
            panel.directoryURL = URL(fileURLWithPath: existing, isDirectory: true)
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        codexWorkingDirectoryDraft = selectedURL.path
        codexWorkingDirectoryDraftError = nil
    }

    func applyCodexSessionSettingsDraft() {
        switch ChatEditorDraftSupport.applyCodexSessionSettingsDraft(
            workingDirectoryDraft: codexWorkingDirectoryDraft,
            sandboxModeDraft: codexSandboxModeDraft,
            personalityDraft: codexPersonalityDraft,
            controls: controls
        ) {
        case .success(let result):
            controls = result.controls
            persistControlsToConversation()
            codexWorkingDirectoryDraft = result.normalizedPath ?? ""
            codexWorkingDirectoryDraftError = nil
            showingCodexSessionSettingsSheet = false
        case .failure(let error):
            codexWorkingDirectoryDraftError = error.localizedDescription
        }
    }

    func resolveCodexInteraction(_ item: PendingCodexInteraction, response: CodexInteractionResponse) {
        Task {
            await item.request.resolve(response)
        }
        pendingCodexInteractions.removeAll { $0.id == item.id }
    }

    func resolveAgentApproval(_ item: PendingAgentApproval, choice: AgentApprovalChoice) {
        Task {
            await item.request.resolve(choice)
        }
        pendingAgentApprovals.removeAll { $0.id == item.id }
    }

    func normalizedCodexWorkingDirectoryPath(from raw: String) -> String? {
        ChatEditorDraftSupport.normalizedCodexWorkingDirectoryPath(from: raw)
    }

    var isImageGenerationDraftValid: Bool {
        ChatEditorDraftSupport.isImageGenerationDraftValid(
            seedDraft: imageGenerationSeedDraft,
            compressionQualityDraft: imageGenerationCompressionQualityDraft
        )
    }

    @discardableResult
    func applyImageGenerationDraft() -> Bool {
        switch ChatEditorDraftSupport.applyImageGenerationDraft(
            draft: imageGenerationDraft,
            seedDraft: imageGenerationSeedDraft,
            compressionQualityDraft: imageGenerationCompressionQualityDraft,
            supportsCurrentModelImageSizeControl: supportsCurrentModelImageSizeControl,
            supportedCurrentModelImageSizes: supportedCurrentModelImageSizes,
            supportedCurrentModelImageAspectRatios: supportedCurrentModelImageAspectRatios,
            providerType: providerType
        ) {
        case .success(let draft):
            controls.imageGeneration = draft
            persistControlsToConversation()
            imageGenerationDraftError = nil
            return true
        case .failure(let error):
            imageGenerationDraftError = error.localizedDescription
            return false
        }
    }

    func openContextCacheEditor() {
        let prepared = ChatAuxiliaryControlSupport.prepareContextCacheEditorDraft(
            current: controls.contextCache,
            providerType: providerType,
            supportsContextCacheTTL: supportsContextCacheTTL
        )
        contextCacheDraft = prepared.draft
        contextCacheTTLPreset = prepared.ttlPreset
        contextCacheCustomTTLDraft = prepared.customTTLDraft
        contextCacheMinTokensDraft = prepared.minTokensDraft
        contextCacheAdvancedExpanded = prepared.advancedExpanded
        contextCacheDraftError = nil
        showingContextCacheSheet = true
    }

}
