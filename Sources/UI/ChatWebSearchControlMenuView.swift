import SwiftUI

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
    let xaiImageUnderstandingBinding: Binding<Bool>
    let xaiImageSearchBinding: Binding<Bool>
    let xaiVideoUnderstandingBinding: Binding<Bool>
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
                Menu(engineMenuTitle) {
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
                .id("web-search-engine-\(usesBuiltinSearchPlugin)")
            }

            if usesBuiltinSearchPlugin {
                Divider()
                Menu(providerMenuTitle) {
                    ForEach(SearchPluginProvider.allCases) { provider in
                        Button {
                            onSelectSearchProvider(provider)
                        } label: {
                            menuItemLabel(provider.displayName, effectiveSearchPluginProvider == provider)
                        }
                    }
                }
                .id("web-search-provider-\(effectiveSearchPluginProvider.rawValue)")

                Menu(maxResultsMenuTitle) {
                    ForEach([3, 5, 8, 10, 20, 30, 50], id: \.self) { value in
                        Button {
                            onSelectBuiltinMaxResults(value)
                        } label: {
                            menuItemLabel("\(value)", builtinMaxResults == value)
                        }
                    }
                }
                .id("web-search-max-results-\(builtinMaxResults)")

                Menu(recencyMenuTitle) {
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
                .id("web-search-recency-\(builtinRecencyDays.map(String.init) ?? "any")")

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
                    Toggle("Image understanding", isOn: xaiImageUnderstandingBinding)
                    Toggle("Image search", isOn: xaiImageSearchBinding)
                    Toggle("X video understanding", isOn: xaiVideoUnderstandingBinding)

                    if xaiSourcesAreEmpty {
                        Divider()
                        Text("Select at least one source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .mimoTokenPlanOpenAI:
                    Divider()
                    Menu(maxKeywordsMenuTitle) {
                        Button {
                            onSelectAnthropicMaxUses(nil)
                        } label: {
                            menuItemLabel("Default", anthropicMaxUses == nil)
                        }
                        ForEach([1, 3, 5, 10, 20], id: \.self) { value in
                            Button {
                                onSelectAnthropicMaxUses(value)
                            } label: {
                                menuItemLabel("\(value)", anthropicMaxUses == value)
                            }
                        }
                    }
                    .id("web-search-max-keywords-\(anthropicMaxUses.map(String.init) ?? "default")")
                case .anthropic:
                    Divider()
                    Menu(maxUsesMenuTitle) {
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
                    .id("web-search-max-uses-\(anthropicMaxUses.map(String.init) ?? "default")")
                    if supportsAnthropicDynamicFiltering {
                        Toggle("Dynamic Filtering", isOn: anthropicDynamicFilteringBinding)
                    }
                    Divider()
                    Button("Configure…", action: onOpenAnthropicConfiguration)
                case .claudeManagedAgents:
                    EmptyView()
                case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
                     .cohere, .mistral, .deepinfra, .together, .baseten, .gemini, .vertexai, .deepseek,
                     .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic,
                     .fireworks, .cerebras, .sambanova, .databricks, .morphllm, .opencodeGo, .zyphra, .meta, .kimiForCoding, .none:
                    EmptyView()
                }
            }
        }
    }

    private var engineMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Engine",
            current: usesBuiltinSearchPlugin ? "Jin Search" : "Native"
        )
    }

    private var providerMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Provider",
            current: effectiveSearchPluginProvider.displayName
        )
    }

    private var maxResultsMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Max Results",
            current: "\(builtinMaxResults)"
        )
    }

    private var recencyMenuTitle: String {
        let current: String
        if let builtinRecencyDays {
            current = "Past \(builtinRecencyDays)d"
        } else {
            current = "Any time"
        }
        return ChatAuxiliaryControlSupport.nestedMenuTitle("Recency", current: current)
    }

    private var maxKeywordsMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Max Keywords",
            current: anthropicMaxUses.map(String.init) ?? "Default"
        )
    }

    private var maxUsesMenuTitle: String {
        ChatAuxiliaryControlSupport.nestedMenuTitle(
            "Max Uses",
            current: anthropicMaxUses.map(String.init) ?? "Default (10)"
        )
    }
}
