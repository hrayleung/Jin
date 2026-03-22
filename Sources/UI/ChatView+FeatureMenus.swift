import SwiftUI
import SwiftData

// MARK: - Feature Menus

extension ChatView {

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

        if (providerType == .openai || providerType == .openaiWebSocket),
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

        if providerType == .openai || providerType == .openaiWebSocket {
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
}
