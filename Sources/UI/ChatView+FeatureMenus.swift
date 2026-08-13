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
    var anthropicFastModeMenuContent: some View {
        Toggle("Fast mode (beta)", isOn: anthropicFastModeEnabledBinding)

        Divider()

        Text("$30/$150 MTok \u{00B7} extra usage")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var anthropicFastModeEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.anthropicSpeed == .fast },
            set: { enabled in setAnthropicSpeed(enabled ? .fast : nil) }
        )
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
                controls = ChatAuxiliaryControlSupport.clearGoogleMapsLocation(controls: controls)
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
            providerType: providerType,
            controls: controls
        ) {
        case .success(let applied):
            controls = applied.controls
            googleMapsDraft = applied.googleMaps ?? GoogleMapsControls(enabled: false)
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
        let prepared = CodeExecutionSheetSupport.preparedDraft(
            current: controls.codeExecution,
            isEnabled: isCodeExecutionEnabled,
            providerType: providerType
        )
        codeExecutionDraft = prepared.controls
        codeExecutionOpenAIUseExistingContainer = prepared.openAIUseExistingContainer
        codeExecutionOpenAIFileIDsDraft = prepared.openAIFileIDsDraft

        showingCodeExecutionSheet = true
    }

    @discardableResult
    func applyCodeExecutionDraft() -> Bool {
        codeExecutionDraftError = nil

        let applied = CodeExecutionSheetSupport.appliedControls(
            codeExecutionDraft,
            to: controls,
            providerType: providerType,
            openAIUseExistingContainer: codeExecutionOpenAIUseExistingContainer,
            openAIFileIDsDraft: codeExecutionOpenAIFileIDsDraft
        )
        guard applied.isValid else {
            codeExecutionDraftError = applied.errorMessage
            return false
        }

        codeExecutionDraft = applied.codeExecution
        controls = applied.controls
        persistControlsToConversation()
        return true
    }

    func setOpenAIServiceTier(_ serviceTier: OpenAIServiceTier?) {
        controls = ChatAuxiliaryControlSupport.setOpenAIServiceTier(
            serviceTier,
            controls: controls
        )
        persistControlsToConversation()
    }

    func setAnthropicSpeed(_ speed: AnthropicSpeed?) {
        controls = ChatAuxiliaryControlSupport.setAnthropicSpeed(
            speed,
            controls: controls
        )
        persistControlsToConversation()
    }

    var webSearchEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                ChatAuxiliaryControlSupport.webSearchEnabledValue(
                    providerType: providerType,
                    controls: controls
                )
            },
            set: { enabled in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setWebSearchEnabled(
                        enabled,
                        controls: controls,
                        providerType: providerType
                    )
                }
            }
        )
    }

    var anthropicDynamicFilteringBinding: Binding<Bool> {
        Binding(
            get: {
                ChatAuxiliaryControlSupport.anthropicDynamicFilteringValue(
                    controls: controls
                )
            },
            set: { newValue in
                controls = ChatAuxiliaryControlSupport.setAnthropicDynamicFiltering(
                    newValue,
                    controls: controls
                )
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    var webSearchMenuContent: some View {
        let webSearchPluginSettings = WebSearchPluginSettingsStore.load()
        WebSearchControlMenuView(
            isEnabled: webSearchEnabledBinding,
            isWebSearchEnabled: isWebSearchEnabled,
            supportsSearchEngineModeSwitch: supportsSearchEngineModeSwitch,
            usesBuiltinSearchPlugin: usesBuiltinSearchPlugin,
            effectiveSearchPluginProvider: effectiveSearchPluginProvider,
            builtinMaxResults: ChatAuxiliaryControlSupport.builtinSearchMaxResultsValue(
                controls: controls,
                settings: webSearchPluginSettings
            ),
            builtinRecencyDays: ChatAuxiliaryControlSupport.builtinSearchRecencyDaysValue(
                controls: controls
            ),
            providerType: providerType,
            openAIContextSize: ChatAuxiliaryControlSupport.openAIWebSearchContextSizeValue(
                controls: controls
            ),
            perplexityContextSize: ChatAuxiliaryControlSupport.perplexityWebSearchContextSizeValue(
                controls: controls
            ),
            xaiSourcesAreEmpty: ChatAuxiliaryControlSupport.xaiWebSearchSourcesAreEmpty(
                controls: controls
            ),
            anthropicMaxUses: ChatAuxiliaryControlSupport.anthropicWebSearchMaxUsesValue(
                controls: controls
            ),
            supportsAnthropicDynamicFiltering: supportsAnthropicDynamicFiltering,
            builtinSearchIncludeRawBinding: builtinSearchIncludeRawBinding,
            builtinSearchFetchPageBinding: builtinSearchFetchPageBinding,
            builtinSearchFirecrawlExtractBinding: builtinSearchFirecrawlExtractBinding,
            xaiWebBinding: webSearchSourceBinding(.web),
            xaiXBinding: webSearchSourceBinding(.x),
            xaiImageUnderstandingBinding: xaiImageUnderstandingBinding,
            xaiImageSearchBinding: xaiImageSearchBinding,
            xaiVideoUnderstandingBinding: xaiVideoUnderstandingBinding,
            anthropicDynamicFilteringBinding: anthropicDynamicFilteringBinding,
            menuItemLabel: { title, isSelected in
                menuItemLabel(title, isSelected: isSelected)
            },
            onSetSearchEnginePreference: { useJinSearch in
                setSearchEnginePreference(useJinSearch: useJinSearch)
            },
            onSelectSearchProvider: { provider in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setSearchPluginProvider(provider, controls: controls)
                }
            },
            onSelectBuiltinMaxResults: { value in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setSearchPluginMaxResults(value, controls: controls)
                }
            },
            onSelectBuiltinRecencyDays: { value in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setSearchPluginRecencyDays(value, controls: controls)
                }
            },
            onSelectOpenAIContextSize: { size in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setExistingWebSearchContextSize(
                        size,
                        controls: controls
                    )
                }
            },
            onSelectPerplexityContextSize: { size in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setPerplexityWebSearchContextSize(
                        size,
                        controls: controls,
                        providerType: providerType
                    )
                }
            },
            onSelectAnthropicMaxUses: { value in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setAnthropicWebSearchMaxUses(
                        value,
                        controls: controls
                    )
                }
            },
            onOpenAnthropicConfiguration: {
                openAnthropicWebSearchEditor()
            }
        )
    }

    func setSearchEnginePreference(useJinSearch: Bool) {
        applyComposerControlMutation {
            controls = ChatAuxiliaryControlSupport.setSearchEnginePreference(
                useJinSearch: useJinSearch,
                controls: controls
            )
        }
    }

    @ViewBuilder
    var contextCacheMenuContent: some View {
        ContextCacheControlMenuView(
            effectiveMode: effectiveContextCacheMode,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode,
            showsReset: controls.contextCache != nil,
            onTurnOff: {
                controls = ChatAuxiliaryControlSupport.turnOffContextCache(controls: controls)
                persistControlsToConversation()
            },
            onSetImplicit: {
                controls = ChatAuxiliaryControlSupport.setImplicitContextCache(
                    controls: controls,
                    providerType: providerType
                )
                persistControlsToConversation()
            },
            onSetExplicit: {
                controls = ChatAuxiliaryControlSupport.setExplicitContextCache(controls: controls)
                persistControlsToConversation()
            },
            onConfigure: {
                openContextCacheEditor()
            },
            onReset: {
                controls = ChatAuxiliaryControlSupport.resetContextCache(controls: controls)
                persistControlsToConversation()
            },
            menuItemLabel: { title, isSelected in
                menuItemLabel(title, isSelected: isSelected)
            }
        )
    }

    var mcpToolsEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                ChatAuxiliaryControlSupport.mcpToolsEnabledValue(
                    controls: controls
                )
            },
            set: { enabled in
                applyComposerControlMutation {
                    controls = ChatAuxiliaryControlSupport.setMCPToolsEnabled(enabled, controls: controls)
                }
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
            usesCustomServerSelection: ChatAuxiliaryControlSupport.usesCustomMCPServerSelection(
                controls: controls
            ),
            onUseAllServers: {
                resetMCPServerSelection()
            }
        )
    }
}
