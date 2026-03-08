import SwiftUI

struct MCPServerMenuItem: Identifiable {
    let id: String
    let name: String
    let isOn: Binding<Bool>
}

struct ContextCacheControlMenuView<MenuItemLabel: View>: View {
    let effectiveMode: ContextCacheMode
    let supportsExplicitContextCacheMode: Bool
    let showsReset: Bool
    let onTurnOff: () -> Void
    let onSetImplicit: () -> Void
    let onSetExplicit: () -> Void
    let onConfigure: () -> Void
    let onReset: () -> Void
    let menuItemLabel: (String, Bool) -> MenuItemLabel

    var body: some View {
        Button(action: onTurnOff) {
            menuItemLabel("Off", effectiveMode == .off)
        }

        Button(action: onSetImplicit) {
            menuItemLabel("Implicit", effectiveMode == .implicit)
        }

        if supportsExplicitContextCacheMode {
            Button(action: onSetExplicit) {
                menuItemLabel("Explicit", effectiveMode == .explicit)
            }
        }

        Divider()

        Button("Configure…", action: onConfigure)

        if showsReset {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}

struct MCPToolsControlMenuView: View {
    let isEnabled: Binding<Bool>
    let isMCPToolsEnabled: Bool
    let servers: [MCPServerMenuItem]
    let selectedServerIDs: Set<String>
    let usesCustomServerSelection: Bool
    let onUseAllServers: () -> Void

    var body: some View {
        Toggle("MCP Tools", isOn: isEnabled)

        if isMCPToolsEnabled {
            if servers.isEmpty {
                Divider()
                Text("No MCP servers enabled for automatic tool use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                Text("Servers")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(servers) { server in
                    Toggle(server.name, isOn: server.isOn)
                }

                if selectedServerIDs.isEmpty {
                    Divider()
                    Text("Select at least one server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if usesCustomServerSelection {
                    Divider()
                    Button("Use all servers", action: onUseAllServers)
                }
            }
        }
    }
}

struct ReasoningControlMenuView<MenuItemLabel: View>: View {
    let reasoningConfig: ModelReasoningConfig?
    let supportsReasoningDisableToggle: Bool
    let isReasoningEnabled: Bool
    let isAnthropicProvider: Bool
    let supportsCerebrasPreservedThinkingToggle: Bool
    let cerebrasPreserveThinkingBinding: Binding<Bool>
    let availableReasoningEffortLevels: [ReasoningEffort]
    let supportsReasoningSummaryControl: Bool
    let currentReasoningSummary: ReasoningSummary
    let currentReasoningEffort: ReasoningEffort?
    let supportsFireworksReasoningHistoryToggle: Bool
    let fireworksReasoningHistoryOptions: [String]
    let fireworksReasoningHistory: String?
    let budgetTokensLabel: String
    let fireworksReasoningHistoryLabel: (String) -> String
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetReasoningOff: () -> Void
    let onSetReasoningOn: () -> Void
    let onOpenThinkingBudgetEditor: () -> Void
    let onSetReasoningEffort: (ReasoningEffort) -> Void
    let onSetReasoningSummary: (ReasoningSummary) -> Void
    let onSetFireworksReasoningHistory: (String?) -> Void

    @ViewBuilder
    var body: some View {
        if let reasoningConfig, reasoningConfig.type != .none {
            if supportsReasoningDisableToggle {
                Button(action: onSetReasoningOff) {
                    menuItemLabel("Off", !isReasoningEnabled)
                }
            }

            switch reasoningConfig.type {
            case .toggle:
                Button(action: onSetReasoningOn) {
                    menuItemLabel("On", isReasoningEnabled)
                }

                if supportsCerebrasPreservedThinkingToggle {
                    Divider()
                    Toggle("Preserve thinking", isOn: cerebrasPreserveThinkingBinding)
                        .help("Keeps GLM thinking across turns (maps to clear_thinking: false).")
                }

            case .effort:
                if isAnthropicProvider {
                    Button(action: onOpenThinkingBudgetEditor) {
                        menuItemLabel("Configure thinking…", isReasoningEnabled)
                    }
                } else {
                    ForEach(availableReasoningEffortLevels, id: \.self) { level in
                        Button {
                            onSetReasoningEffort(level)
                        } label: {
                            menuItemLabel(
                                level == .xhigh ? "Extreme" : level.displayName,
                                isReasoningEnabled && currentReasoningEffort == level
                            )
                        }
                    }
                }

                if !isAnthropicProvider && supportsReasoningSummaryControl {
                    Divider()
                    Text("Reasoning summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(ReasoningSummary.allCases, id: \.self) { summary in
                        Button {
                            onSetReasoningSummary(summary)
                        } label: {
                            menuItemLabel(summary.displayName, currentReasoningSummary == summary)
                        }
                    }
                }

                if supportsFireworksReasoningHistoryToggle {
                    Divider()
                    Text("Thinking history")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        onSetFireworksReasoningHistory(nil)
                    } label: {
                        menuItemLabel("Default (model)", fireworksReasoningHistory == nil)
                    }

                    ForEach(fireworksReasoningHistoryOptions, id: \.self) { option in
                        Button {
                            onSetFireworksReasoningHistory(option)
                        } label: {
                            menuItemLabel(
                                fireworksReasoningHistoryLabel(option),
                                fireworksReasoningHistory == option
                            )
                        }
                    }
                }

            case .budget:
                Button(action: onOpenThinkingBudgetEditor) {
                    menuItemLabel("Budget tokens… (\(budgetTokensLabel))", isReasoningEnabled)
                }

            case .none:
                EmptyView()
            }
        } else {
            Text("Not supported")
                .foregroundStyle(.secondary)
        }
    }
}

struct WebSearchControlMenuView<MenuItemLabel: View>: View {
    let isEnabled: Binding<Bool>
    let isWebSearchEnabled: Bool
    let supportsSearchEngineModeSwitch: Bool
    let usesBuiltinSearchPlugin: Bool
    let effectiveSearchPluginProvider: SearchPluginProvider
    let builtinMaxResults: Int
    let builtinRecencyDays: Int?
    let providerType: ProviderType?
    let openAIContextSize: WebSearchContextSize
    let perplexityContextSize: WebSearchContextSize
    let xaiSourcesAreEmpty: Bool
    let anthropicMaxUses: Int?
    let supportsAnthropicDynamicFiltering: Bool
    let builtinSearchIncludeRawBinding: Binding<Bool>
    let builtinSearchFetchPageBinding: Binding<Bool>
    let builtinSearchFirecrawlExtractBinding: Binding<Bool>
    let xaiWebBinding: Binding<Bool>
    let xaiXBinding: Binding<Bool>
    let anthropicDynamicFilteringBinding: Binding<Bool>
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetSearchEnginePreference: (Bool) -> Void
    let onSelectSearchProvider: (SearchPluginProvider) -> Void
    let onSelectBuiltinMaxResults: (Int) -> Void
    let onSelectBuiltinRecencyDays: (Int?) -> Void
    let onSelectOpenAIContextSize: (WebSearchContextSize) -> Void
    let onSelectPerplexityContextSize: (WebSearchContextSize) -> Void
    let onSelectAnthropicMaxUses: (Int?) -> Void
    let onOpenAnthropicConfiguration: () -> Void

    @ViewBuilder
    var body: some View {
        Toggle("Web Search", isOn: isEnabled)
        if isWebSearchEnabled {
            if supportsSearchEngineModeSwitch {
                Divider()
                Menu("Engine") {
                    Button {
                        onSetSearchEnginePreference(false)
                    } label: {
                        menuItemLabel("Native", !usesBuiltinSearchPlugin)
                    }

                    Button {
                        onSetSearchEnginePreference(true)
                    } label: {
                        menuItemLabel("Jin Search", usesBuiltinSearchPlugin)
                    }
                }
            }

            if usesBuiltinSearchPlugin {
                Divider()
                Menu("Provider") {
                    ForEach(SearchPluginProvider.allCases) { provider in
                        Button {
                            onSelectSearchProvider(provider)
                        } label: {
                            menuItemLabel(provider.displayName, effectiveSearchPluginProvider == provider)
                        }
                    }
                }

                Menu("Max Results") {
                    ForEach([3, 5, 8, 10, 20, 30, 50], id: \.self) { value in
                        Button {
                            onSelectBuiltinMaxResults(value)
                        } label: {
                            menuItemLabel("\(value)", builtinMaxResults == value)
                        }
                    }
                }

                Menu("Recency") {
                    Button {
                        onSelectBuiltinRecencyDays(nil)
                    } label: {
                        menuItemLabel("Any time", builtinRecencyDays == nil)
                    }

                    ForEach([1, 7, 30, 90], id: \.self) { value in
                        Button {
                            onSelectBuiltinRecencyDays(value)
                        } label: {
                            menuItemLabel("Past \(value)d", builtinRecencyDays == value)
                        }
                    }
                }

                Divider()
                Toggle("Include raw snippets", isOn: builtinSearchIncludeRawBinding)

                if effectiveSearchPluginProvider == .jina {
                    Toggle("Fetch pages via Reader", isOn: builtinSearchFetchPageBinding)
                } else if effectiveSearchPluginProvider == .firecrawl {
                    Toggle("Extract markdown", isOn: builtinSearchFirecrawlExtractBinding)
                }
            } else {
                switch providerType {
                case .openai, .openaiWebSocket:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        Button {
                            onSelectOpenAIContextSize(size)
                        } label: {
                            menuItemLabel(size.displayName, openAIContextSize == size)
                        }
                    }
                case .perplexity:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        Button {
                            onSelectPerplexityContextSize(size)
                        } label: {
                            menuItemLabel(size.displayName, perplexityContextSize == size)
                        }
                    }
                case .xai:
                    Divider()
                    Toggle("Web", isOn: xaiWebBinding)
                    Toggle("X", isOn: xaiXBinding)

                    if xaiSourcesAreEmpty {
                        Divider()
                        Text("Select at least one source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .anthropic:
                    Divider()
                    Menu("Max Uses") {
                        Button {
                            onSelectAnthropicMaxUses(nil)
                        } label: {
                            menuItemLabel("Default (10)", anthropicMaxUses == nil)
                        }
                        ForEach([1, 3, 5, 10, 20], id: \.self) { value in
                            Button {
                                onSelectAnthropicMaxUses(value)
                            } label: {
                                menuItemLabel("\(value)", anthropicMaxUses == value)
                            }
                        }
                    }
                    if supportsAnthropicDynamicFiltering {
                        Toggle("Dynamic Filtering", isOn: anthropicDynamicFilteringBinding)
                    }
                    Divider()
                    Button("Configure…", action: onOpenAnthropicConfiguration)
                case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
                     .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
                     .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
                    EmptyView()
                }
            }
        }
    }
}

struct GoogleVideoGenerationMenuView<MenuItemLabel: View>: View {
    let isVeo3: Bool
    let isVertexProvider: Bool
    let isConfigured: Bool
    let currentDurationSeconds: Int?
    let currentAspectRatio: GoogleVideoAspectRatio?
    let currentResolution: GoogleVideoResolution?
    let currentPersonGeneration: GoogleVideoPersonGeneration?
    let generateAudioBinding: Binding<Bool>
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetDurationSeconds: (Int?) -> Void
    let onSetAspectRatio: (GoogleVideoAspectRatio?) -> Void
    let onSetResolution: (GoogleVideoResolution?) -> Void
    let onSetPersonGeneration: (GoogleVideoPersonGeneration?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("Google Veo")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button {
                onSetDurationSeconds(nil)
            } label: {
                menuItemLabel("Default", currentDurationSeconds == nil)
            }
            ForEach([4, 6, 8], id: \.self) { seconds in
                Button {
                    onSetDurationSeconds(seconds)
                } label: {
                    menuItemLabel("\(seconds)s", currentDurationSeconds == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button {
                onSetAspectRatio(nil)
            } label: {
                menuItemLabel("Default (16:9)", currentAspectRatio == nil)
            }
            ForEach(GoogleVideoAspectRatio.allCases, id: \.self) { ratio in
                Button {
                    onSetAspectRatio(ratio)
                } label: {
                    menuItemLabel(ratio.displayName, currentAspectRatio == ratio)
                }
            }
        }

        if isVeo3 {
            Menu("Resolution") {
                Button {
                    onSetResolution(nil)
                } label: {
                    menuItemLabel("Default (720p)", currentResolution == nil)
                }
                ForEach(GoogleVideoResolution.allCases, id: \.self) { resolution in
                    Button {
                        onSetResolution(resolution)
                    } label: {
                        menuItemLabel(resolution.displayName, currentResolution == resolution)
                    }
                }
            }
        }

        Menu("Person generation") {
            Button {
                onSetPersonGeneration(nil)
            } label: {
                menuItemLabel("Default", currentPersonGeneration == nil)
            }
            ForEach(GoogleVideoPersonGeneration.allCases, id: \.self) { personGeneration in
                Button {
                    onSetPersonGeneration(personGeneration)
                } label: {
                    menuItemLabel(personGeneration.displayName, currentPersonGeneration == personGeneration)
                }
            }
        }

        if isVertexProvider, isVeo3 {
            Toggle("Generate audio", isOn: generateAudioBinding)
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}

struct XAIVideoGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let currentDuration: Int?
    let currentAspectRatio: XAIAspectRatio?
    let currentResolution: XAIVideoResolution?
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetDuration: (Int?) -> Void
    let onSetAspectRatio: (XAIAspectRatio?) -> Void
    let onSetResolution: (XAIVideoResolution?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("xAI Video")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button {
                onSetDuration(nil)
            } label: {
                menuItemLabel("Default (8s)", currentDuration == nil)
            }
            ForEach([3, 5, 8, 10, 15], id: \.self) { seconds in
                Button {
                    onSetDuration(seconds)
                } label: {
                    menuItemLabel("\(seconds)s", currentDuration == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button {
                onSetAspectRatio(nil)
            } label: {
                menuItemLabel("Default (16:9)", currentAspectRatio == nil)
            }
            ForEach(
                [XAIAspectRatio.ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio3x2, .ratio2x3],
                id: \.self
            ) { ratio in
                Button {
                    onSetAspectRatio(ratio)
                } label: {
                    menuItemLabel(ratio.displayName, currentAspectRatio == ratio)
                }
            }
        }

        Menu("Resolution") {
            Button {
                onSetResolution(nil)
            } label: {
                menuItemLabel("Default (480p)", currentResolution == nil)
            }
            ForEach(XAIVideoResolution.allCases, id: \.self) { resolution in
                Button {
                    onSetResolution(resolution)
                } label: {
                    menuItemLabel(resolution.displayName, currentResolution == resolution)
                }
            }
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}

struct XAIImageGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let currentCount: Int?
    let selectedAspectRatio: XAIAspectRatio?
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetCount: (Int?) -> Void
    let onSetAspectRatio: (XAIAspectRatio?) -> Void
    let onReset: () -> Void

    var body: some View {
        Text("xAI Image")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Count") {
            Button {
                onSetCount(nil)
            } label: {
                menuItemLabel("Default", currentCount == nil)
            }
            ForEach([1, 2, 4], id: \.self) { count in
                Button {
                    onSetCount(count)
                } label: {
                    menuItemLabel("\(count)", currentCount == count)
                }
            }
        }

        Menu("Aspect ratio") {
            Button {
                onSetAspectRatio(nil)
            } label: {
                menuItemLabel("Default", selectedAspectRatio == nil)
            }
            ForEach(XAIAspectRatio.allCases, id: \.self) { ratio in
                Button {
                    onSetAspectRatio(ratio)
                } label: {
                    menuItemLabel(ratio.displayName, selectedAspectRatio == ratio)
                }
            }
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}

struct OpenAIImageGenerationMenuView<MenuItemLabel: View>: View {
    let isConfigured: Bool
    let isGPTImageModel: Bool
    let isDallE3: Bool
    let showsInputFidelity: Bool
    let currentCount: Int?
    let currentSize: OpenAIImageSize?
    let currentQuality: OpenAIImageQuality?
    let currentStyle: OpenAIImageStyle?
    let currentBackground: OpenAIImageBackground?
    let currentOutputFormat: OpenAIImageOutputFormat?
    let currentOutputCompression: Int?
    let currentModeration: OpenAIImageModeration?
    let currentInputFidelity: OpenAIImageInputFidelity?
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetCount: (Int?) -> Void
    let onSetSize: (OpenAIImageSize?) -> Void
    let onSetQuality: (OpenAIImageQuality?) -> Void
    let onSetStyle: (OpenAIImageStyle?) -> Void
    let onSetBackground: (OpenAIImageBackground?) -> Void
    let onSetOutputFormat: (OpenAIImageOutputFormat?) -> Void
    let onSetOutputCompression: (Int?) -> Void
    let onSetModeration: (OpenAIImageModeration?) -> Void
    let onSetInputFidelity: (OpenAIImageInputFidelity?) -> Void
    let onReset: () -> Void

    private var sizes: [OpenAIImageSize] {
        if isGPTImageModel { return OpenAIImageSize.gptImageSizes }
        if isDallE3 { return OpenAIImageSize.dallE3Sizes }
        return OpenAIImageSize.dallE2Sizes
    }

    private var qualities: [OpenAIImageQuality] {
        if isGPTImageModel { return OpenAIImageQuality.gptImageQualities }
        if isDallE3 { return OpenAIImageQuality.dallE3Qualities }
        return []
    }

    var body: some View {
        Text("OpenAI Image")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Count") {
            Button {
                onSetCount(nil)
            } label: {
                menuItemLabel("Default (1)", currentCount == nil)
            }
            ForEach([1, 2, 4], id: \.self) { count in
                Button {
                    onSetCount(count)
                } label: {
                    menuItemLabel("\(count)", currentCount == count)
                }
            }
        }

        Menu("Size") {
            Button {
                onSetSize(nil)
            } label: {
                menuItemLabel("Default", currentSize == nil)
            }
            ForEach(sizes, id: \.self) { size in
                Button {
                    onSetSize(size)
                } label: {
                    menuItemLabel(size.displayName, currentSize == size)
                }
            }
        }

        if !qualities.isEmpty {
            Menu("Quality") {
                Button {
                    onSetQuality(nil)
                } label: {
                    menuItemLabel("Default", currentQuality == nil)
                }
                ForEach(qualities, id: \.self) { quality in
                    Button {
                        onSetQuality(quality)
                    } label: {
                        menuItemLabel(quality.displayName, currentQuality == quality)
                    }
                }
            }
        }

        if isDallE3 {
            Menu("Style") {
                Button {
                    onSetStyle(nil)
                } label: {
                    menuItemLabel("Default (Vivid)", currentStyle == nil)
                }
                ForEach(OpenAIImageStyle.allCases, id: \.self) { style in
                    Button {
                        onSetStyle(style)
                    } label: {
                        menuItemLabel(style.displayName, currentStyle == style)
                    }
                }
            }
        }

        if isGPTImageModel {
            Menu("Background") {
                Button {
                    onSetBackground(nil)
                } label: {
                    menuItemLabel("Default (Auto)", currentBackground == nil)
                }
                ForEach(OpenAIImageBackground.allCases, id: \.self) { background in
                    Button {
                        onSetBackground(background)
                    } label: {
                        menuItemLabel(background.displayName, currentBackground == background)
                    }
                }
            }

            Menu("Output Format") {
                Button {
                    onSetOutputFormat(nil)
                } label: {
                    menuItemLabel("Default (PNG)", currentOutputFormat == nil)
                }
                ForEach(OpenAIImageOutputFormat.allCases, id: \.self) { format in
                    Button {
                        onSetOutputFormat(format)
                    } label: {
                        menuItemLabel(format.displayName, currentOutputFormat == format)
                    }
                }
            }

            if currentOutputFormat == .jpeg || currentOutputFormat == .webp {
                Menu("Compression") {
                    Button {
                        onSetOutputCompression(nil)
                    } label: {
                        menuItemLabel("Default (100)", currentOutputCompression == nil)
                    }
                    ForEach([25, 50, 75, 100], id: \.self) { level in
                        Button {
                            onSetOutputCompression(level)
                        } label: {
                            menuItemLabel("\(level)%", currentOutputCompression == level)
                        }
                    }
                }
            }

            Menu("Moderation") {
                Button {
                    onSetModeration(nil)
                } label: {
                    menuItemLabel("Default (Auto)", currentModeration == nil)
                }
                ForEach(OpenAIImageModeration.allCases, id: \.self) { moderation in
                    Button {
                        onSetModeration(moderation)
                    } label: {
                        menuItemLabel(moderation.displayName, currentModeration == moderation)
                    }
                }
            }

            if showsInputFidelity {
                Menu("Input Fidelity") {
                    Button {
                        onSetInputFidelity(nil)
                    } label: {
                        menuItemLabel("Default (Low)", currentInputFidelity == nil)
                    }
                    ForEach(OpenAIImageInputFidelity.allCases, id: \.self) { fidelity in
                        Button {
                            onSetInputFidelity(fidelity)
                        } label: {
                            menuItemLabel(fidelity.displayName, currentInputFidelity == fidelity)
                        }
                    }
                }
            }
        }

        if isConfigured {
            Divider()
            Button("Reset", role: .destructive, action: onReset)
        }
    }
}