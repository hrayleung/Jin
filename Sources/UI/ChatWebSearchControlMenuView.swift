import SwiftUI

struct WebSearchControlMenuView: View {
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
                    JinMenuSelectionItem("Native", isSelected: !usesBuiltinSearchPlugin) {
                        onSetSearchEnginePreference(false)
                    }

                    JinMenuSelectionItem("Jin Search", isSelected: usesBuiltinSearchPlugin) {
                        onSetSearchEnginePreference(true)
                    }
                }
            }

            if usesBuiltinSearchPlugin {
                Divider()
                Menu(providerMenuTitle) {
                    ForEach(SearchPluginProvider.allCases) { provider in
                        JinMenuSelectionItem(
                            provider.displayName,
                            isSelected: effectiveSearchPluginProvider == provider
                        ) {
                            onSelectSearchProvider(provider)
                        }
                    }
                }

                Menu(maxResultsMenuTitle) {
                    ForEach([3, 5, 8, 10, 20, 30, 50], id: \.self) { value in
                        JinMenuSelectionItem("\(value)", isSelected: builtinMaxResults == value) {
                            onSelectBuiltinMaxResults(value)
                        }
                    }
                }

                Menu(recencyMenuTitle) {
                    JinMenuSelectionItem("Any time", isSelected: builtinRecencyDays == nil) {
                        onSelectBuiltinRecencyDays(nil)
                    }

                    ForEach([1, 7, 30, 90], id: \.self) { value in
                        JinMenuSelectionItem("Past \(value)d", isSelected: builtinRecencyDays == value) {
                            onSelectBuiltinRecencyDays(value)
                        }
                    }
                }

                Divider()
                Toggle("Include raw snippets", isOn: builtinSearchIncludeRawBinding)

                switch effectiveSearchPluginProvider {
                case .jina:
                    Toggle("Fetch pages via Reader", isOn: builtinSearchFetchPageBinding)
                case .tinyfish:
                    Toggle("Fetch page content", isOn: builtinSearchFetchPageBinding)
                case .parallel:
                    Toggle("Extract result pages", isOn: builtinSearchFetchPageBinding)
                case .firecrawl:
                    Toggle("Extract markdown", isOn: builtinSearchFirecrawlExtractBinding)
                case .exa, .brave, .tavily, .perplexity:
                    EmptyView()
                }
            } else {
                switch providerType {
                case .openai, .openaiWebSocket, .router:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        JinMenuSelectionItem(size.displayName, isSelected: openAIContextSize == size) {
                            onSelectOpenAIContextSize(size)
                        }
                    }
                case .perplexity:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        JinMenuSelectionItem(size.displayName, isSelected: perplexityContextSize == size) {
                            onSelectPerplexityContextSize(size)
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
                        JinMenuSelectionItem("Default", isSelected: anthropicMaxUses == nil) {
                            onSelectAnthropicMaxUses(nil)
                        }
                        ForEach([1, 3, 5, 10, 20], id: \.self) { value in
                            JinMenuSelectionItem("\(value)", isSelected: anthropicMaxUses == value) {
                                onSelectAnthropicMaxUses(value)
                            }
                        }
                    }
                case .anthropic:
                    Divider()
                    Menu(maxUsesMenuTitle) {
                        JinMenuSelectionItem("Default (10)", isSelected: anthropicMaxUses == nil) {
                            onSelectAnthropicMaxUses(nil)
                        }
                        ForEach([1, 3, 5, 10, 20], id: \.self) { value in
                            JinMenuSelectionItem("\(value)", isSelected: anthropicMaxUses == value) {
                                onSelectAnthropicMaxUses(value)
                            }
                        }
                    }
                    if supportsAnthropicDynamicFiltering {
                        Toggle("Dynamic Filtering", isOn: anthropicDynamicFilteringBinding)
                    }
                    Divider()
                    Button("Configure…", action: onOpenAnthropicConfiguration)
                case .claudeManagedAgents:
                    EmptyView()
                case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
                     .cohere, .mistral, .deepinfra, .together, .baseten, .runinfra, .gemini, .vertexai, .deepseek,
                     .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic,
                     .fireworks, .cerebras, .sambanova, .databricks, .modal, .morphllm, .opencodeGo, .zyphra, .makora, .meta, .kimiForCoding, .none:
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
