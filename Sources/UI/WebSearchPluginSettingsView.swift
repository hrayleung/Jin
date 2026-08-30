import SwiftUI

struct WebSearchPluginSettingsView: View {
    @AppStorage(AppPreferenceKeys.pluginWebSearchEnabled) private var pluginEnabled = true
    @AppStorage(AppPreferenceKeys.pluginWebSearchDefaultProvider) private var defaultProviderRaw = SearchPluginProvider.exa.rawValue
    @AppStorage(AppPreferenceKeys.pluginWebSearchDefaultMaxResults) private var defaultMaxResults = 8
    @AppStorage(AppPreferenceKeys.pluginWebSearchDefaultRecencyDays) private var defaultRecencyDays = 0

    @AppStorage(AppPreferenceKeys.pluginWebSearchExaAPIKey) private var exaAPIKey = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchBraveAPIKey) private var braveAPIKey = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchJinaAPIKey) private var jinaAPIKey = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey) private var firecrawlAPIKey = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyAPIKey) private var tavilyAPIKey = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchPerplexityAPIKey) private var perplexityAPIKey = ""

    @AppStorage(AppPreferenceKeys.pluginWebSearchExaSearchType) private var exaSearchTypeRaw = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchExaCategory) private var exaCategory = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchExaUserLocation) private var exaUserLocation = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchExaModeration) private var exaModeration = false
    @AppStorage(AppPreferenceKeys.pluginWebSearchBraveCountry) private var braveCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchBraveLanguage) private var braveLanguage = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchBraveSafesearch) private var braveSafesearch = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchJinaReadPages) private var jinaReadPages = true
    @AppStorage(AppPreferenceKeys.pluginWebSearchJinaCountry) private var jinaCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchJinaLocale) private var jinaLocale = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlExtractContent) private var firecrawlExtractContent = true
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlCountry) private var firecrawlCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlSources) private var firecrawlSourcesRaw = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilySearchDepth) private var tavilySearchDepth = "basic"
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyTopic) private var tavilyTopic = "general"
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyCountry) private var tavilyCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyAutoParameters) private var tavilyAutoParameters = false
    @AppStorage(AppPreferenceKeys.pluginWebSearchPerplexityCountry) private var perplexityCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchPerplexityLanguage) private var perplexityLanguage = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTinyFishAPIKey) private var tinyfishAPIKey = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTinyFishLocation) private var tinyfishLocation = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTinyFishLanguage) private var tinyfishLanguage = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTinyFishDomainType) private var tinyfishDomainTypeRaw = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTinyFishFetchPages) private var tinyfishFetchPages = false
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlLocation) private var firecrawlLocation = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlSafe) private var firecrawlSafe = false
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyLanguage) private var tavilyLanguage = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyFilterByLanguage) private var tavilyFilterByLanguage = false
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilySafeSearch) private var tavilySafeSearch = false
    @AppStorage(AppPreferenceKeys.pluginWebSearchParallelAPIKey) private var parallelAPIKey = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchParallelSearchMode) private var parallelSearchModeRaw = ParallelSearchMode.fast.rawValue
    @AppStorage(AppPreferenceKeys.pluginWebSearchParallelLocation) private var parallelLocation = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchParallelExtractPages) private var parallelExtractPages = false

    @State private var isExaKeyVisible = false
    @State private var isBraveKeyVisible = false
    @State private var isJinaKeyVisible = false
    @State private var isFirecrawlKeyVisible = false
    @State private var isTavilyKeyVisible = false
    @State private var isPerplexityKeyVisible = false
    @State private var isTinyFishKeyVisible = false
    @State private var isParallelKeyVisible = false

    private var defaultProvider: SearchPluginProvider {
        WebSearchPluginSettingsSupport.provider(rawValue: defaultProviderRaw)
    }

    private var configuredProviders: [SearchPluginProvider] {
        WebSearchPluginSettingsSupport.configuredProviders(apiKeys: providerAPIKeys)
    }

    private var effectiveDefaultMaxResults: Int {
        WebSearchPluginSettingsSupport.effectiveMaxResults(defaultMaxResults)
    }

    private var providerAPIKeys: [SearchPluginProvider: String] {
        [
            .exa: exaAPIKey,
            .brave: braveAPIKey,
            .jina: jinaAPIKey,
            .firecrawl: firecrawlAPIKey,
            .tavily: tavilyAPIKey,
            .perplexity: perplexityAPIKey,
            .tinyfish: tinyfishAPIKey,
            .parallel: parallelAPIKey
        ]
    }

    var body: some View {
        formContentWithAPIKeyObservers
            .modifier(ExaProviderObservers(
                exaSearchTypeRaw: exaSearchTypeRaw,
                exaCategory: exaCategory,
                exaUserLocation: exaUserLocation,
                exaModeration: exaModeration,
                onChange: notifyCredentialsChanged
            ))
            .modifier(BraveProviderObservers(
                braveCountry: braveCountry,
                braveLanguage: braveLanguage,
                braveSafesearch: braveSafesearch,
                onChange: notifyCredentialsChanged
            ))
            .modifier(JinaProviderObservers(
                jinaReadPages: jinaReadPages,
                jinaCountry: jinaCountry,
                jinaLocale: jinaLocale,
                onChange: notifyCredentialsChanged
            ))
            .modifier(FirecrawlProviderObservers(
                firecrawlExtractContent: firecrawlExtractContent,
                firecrawlCountry: firecrawlCountry,
                firecrawlLocation: firecrawlLocation,
                firecrawlSafe: firecrawlSafe,
                firecrawlSourcesRaw: firecrawlSourcesRaw,
                onChange: notifyCredentialsChanged
            ))
            .modifier(TavilyProviderObservers(
                tavilySearchDepth: tavilySearchDepth,
                tavilyTopic: tavilyTopic,
                tavilyCountry: tavilyCountry,
                tavilyAutoParameters: tavilyAutoParameters,
                tavilyLanguage: tavilyLanguage,
                tavilyFilterByLanguage: tavilyFilterByLanguage,
                tavilySafeSearch: tavilySafeSearch,
                onChange: notifyCredentialsChanged
            ))
            .modifier(PerplexityProviderObservers(
                perplexityCountry: perplexityCountry,
                perplexityLanguage: perplexityLanguage,
                onChange: notifyCredentialsChanged
            ))
            .modifier(TinyFishProviderObservers(
                tinyfishLocation: tinyfishLocation,
                tinyfishLanguage: tinyfishLanguage,
                tinyfishDomainTypeRaw: tinyfishDomainTypeRaw,
                tinyfishFetchPages: tinyfishFetchPages,
                onChange: notifyCredentialsChanged
            ))
            .modifier(ParallelProviderObservers(
                parallelSearchModeRaw: parallelSearchModeRaw,
                parallelLocation: parallelLocation,
                parallelExtractPages: parallelExtractPages,
                onChange: notifyCredentialsChanged
            ))
            .onAppear {
                normalizeLegacyExaPreferencesIfNeeded()
            }
    }

    private var formContentWithAPIKeyObservers: some View {
        formContent
            .onChange(of: pluginEnabled) { _, _ in notifyCredentialsChanged() }
            .onChange(of: defaultProviderRaw) { _, _ in notifyCredentialsChanged() }
            .onChange(of: defaultMaxResults) { _, _ in notifyCredentialsChanged() }
            .onChange(of: defaultRecencyDays) { _, _ in notifyCredentialsChanged() }
            .onChange(of: exaAPIKey) { _, _ in notifyCredentialsChanged() }
            .onChange(of: braveAPIKey) { _, _ in notifyCredentialsChanged() }
            .onChange(of: jinaAPIKey) { _, _ in notifyCredentialsChanged() }
            .onChange(of: firecrawlAPIKey) { _, _ in notifyCredentialsChanged() }
            .onChange(of: tavilyAPIKey) { _, _ in notifyCredentialsChanged() }
            .onChange(of: perplexityAPIKey) { _, _ in notifyCredentialsChanged() }
            .onChange(of: tinyfishAPIKey) { _, _ in notifyCredentialsChanged() }
            .onChange(of: parallelAPIKey) { _, _ in notifyCredentialsChanged() }
    }

    private var formContent: some View {
        JinSettingsPage {
            JinSettingsSection(
                "Jin Search",
                detail: "When a chat uses Jin Search instead of a model’s native web search, these defaults apply."
            ) {
                JinSettingsToggleRow(
                    "Enable",
                    supportingText: configuredProviders.isEmpty
                        ? "Add an API key below before chats can use Jin Search."
                        : "\(WebSearchPluginSettingsSupport.configuredCountText(configuredProviders)) engines have keys.",
                    isOn: $pluginEnabled
                )
            }

            defaultsSection
            selectedEngineSection
        }
        .navigationTitle("Web Search")
    }

    private var defaultsSection: some View {
        JinSettingsSection(
            "Defaults",
            detail: "Used when a chat does not override the engine, result count, or recency."
        ) {
            JinSettingsPickerRow(
                "Engine",
                supportingText: "Keys and options below apply to this engine.",
                selection: $defaultProviderRaw
            ) {
                ForEach(SearchPluginProvider.allCases) { provider in
                    enginePickerLabel(provider).tag(provider.rawValue)
                }
            }

            Stepper(
                value: Binding(
                    get: { effectiveDefaultMaxResults },
                    set: { defaultMaxResults = WebSearchPluginSettingsSupport.effectiveMaxResults($0) }
                ),
                in: 1...50
            ) {
                Text("Max results: \(effectiveDefaultMaxResults)")
            }

            JinSettingsPickerRow("Recency", selection: $defaultRecencyDays) {
                ForEach(WebSearchPluginSettingsSupport.recencyChoices) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
        }
    }

    private var selectedEngineSection: some View {
        JinSettingsSection(defaultProvider.displayName) {
            WebSearchAPIKeyRow(
                label: "API Key",
                text: apiKeyBinding(for: defaultProvider),
                isRevealed: keyVisibilityBinding(for: defaultProvider),
                onClear: {
                    apiKeyBinding(for: defaultProvider).wrappedValue = ""
                    keyVisibilityBinding(for: defaultProvider).wrappedValue = false
                }
            )

            if let signupURL = defaultProvider.signupURL {
                Link("Get an API key", destination: signupURL)
                    .font(.caption)
            }

            providerAdvancedContent()
        }
    }

    private func enginePickerLabel(_ provider: SearchPluginProvider) -> some View {
        HStack(spacing: JinSpacing.small) {
            MCPIconView(iconID: provider.mcpIconID, fallbackSystemName: "magnifyingglass", size: 14)
            Text(provider.displayName)
            if WebSearchPluginSettingsSupport.hasConfiguredCredential(providerAPIKeys[provider] ?? "") {
                Spacer(minLength: JinSpacing.small)
                Text("Key")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func providerAdvancedContent() -> some View {
        WebSearchAdvancedProviderSettingsView(
            provider: defaultProvider,
            exaSearchTypeRaw: $exaSearchTypeRaw,
            exaCategory: $exaCategory,
            exaUserLocation: $exaUserLocation,
            exaModeration: $exaModeration,
            braveCountry: $braveCountry,
            braveLanguage: $braveLanguage,
            braveSafesearch: $braveSafesearch,
            jinaReadPages: $jinaReadPages,
            jinaCountry: $jinaCountry,
            jinaLocale: $jinaLocale,
            firecrawlExtractContent: $firecrawlExtractContent,
            firecrawlCountry: $firecrawlCountry,
            firecrawlSourcesRaw: $firecrawlSourcesRaw,
            tavilySearchDepth: $tavilySearchDepth,
            tavilyTopic: $tavilyTopic,
            tavilyCountry: $tavilyCountry,
            tavilyAutoParameters: $tavilyAutoParameters,
            perplexityCountry: $perplexityCountry,
            perplexityLanguage: $perplexityLanguage,
            tinyfishLocation: $tinyfishLocation,
            tinyfishLanguage: $tinyfishLanguage,
            tinyfishDomainTypeRaw: $tinyfishDomainTypeRaw,
            tinyfishFetchPages: $tinyfishFetchPages,
            firecrawlLocation: $firecrawlLocation,
            firecrawlSafe: $firecrawlSafe,
            tavilyLanguage: $tavilyLanguage,
            tavilyFilterByLanguage: $tavilyFilterByLanguage,
            tavilySafeSearch: $tavilySafeSearch,
            parallelSearchModeRaw: $parallelSearchModeRaw,
            parallelLocation: $parallelLocation,
            parallelExtractPages: $parallelExtractPages
        )
    }

    private func apiKeyBinding(for provider: SearchPluginProvider) -> Binding<String> {
        switch provider {
        case .exa:
            return $exaAPIKey
        case .brave:
            return $braveAPIKey
        case .jina:
            return $jinaAPIKey
        case .firecrawl:
            return $firecrawlAPIKey
        case .tavily:
            return $tavilyAPIKey
        case .perplexity:
            return $perplexityAPIKey
        case .tinyfish:
            return $tinyfishAPIKey
        case .parallel:
            return $parallelAPIKey
        }
    }

    private func keyVisibilityBinding(for provider: SearchPluginProvider) -> Binding<Bool> {
        switch provider {
        case .exa:
            return $isExaKeyVisible
        case .brave:
            return $isBraveKeyVisible
        case .jina:
            return $isJinaKeyVisible
        case .firecrawl:
            return $isFirecrawlKeyVisible
        case .tavily:
            return $isTavilyKeyVisible
        case .perplexity:
            return $isPerplexityKeyVisible
        case .tinyfish:
            return $isTinyFishKeyVisible
        case .parallel:
            return $isParallelKeyVisible
        }
    }

    /// Rewrites retired Exa AppStorage values so pickers show a valid selection.
    private func normalizeLegacyExaPreferencesIfNeeded() {
        if let resolvedType = ExaSearchType.resolved(from: exaSearchTypeRaw),
           resolvedType.wireValue != exaSearchTypeRaw {
            exaSearchTypeRaw = resolvedType.wireValue
        }

        if let resolvedCategory = ExaCategory.resolved(from: exaCategory),
           resolvedCategory.rawValue != exaCategory {
            exaCategory = resolvedCategory.rawValue
        }
    }

    private func notifyCredentialsChanged() {
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }
}
