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
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlLanguage) private var firecrawlLanguage = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlSources) private var firecrawlSourcesRaw = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilySearchDepth) private var tavilySearchDepth = "basic"
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyTopic) private var tavilyTopic = "general"
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyCountry) private var tavilyCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyAutoParameters) private var tavilyAutoParameters = false
    @AppStorage(AppPreferenceKeys.pluginWebSearchPerplexityCountry) private var perplexityCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchPerplexityLanguage) private var perplexityLanguage = ""

    @State private var isExaKeyVisible = false
    @State private var isBraveKeyVisible = false
    @State private var isJinaKeyVisible = false
    @State private var isFirecrawlKeyVisible = false
    @State private var isTavilyKeyVisible = false
    @State private var isPerplexityKeyVisible = false
    @State private var credentialEditorProviderRaw = SearchPluginProvider.exa.rawValue
    @State private var hasInitializedCredentialEditorProvider = false

    private var defaultProvider: SearchPluginProvider {
        WebSearchPluginSettingsSupport.provider(rawValue: defaultProviderRaw)
    }

    private var credentialEditorProvider: SearchPluginProvider {
        WebSearchPluginSettingsSupport.provider(rawValue: credentialEditorProviderRaw)
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
            .perplexity: perplexityAPIKey
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
                firecrawlLanguage: firecrawlLanguage,
                firecrawlSourcesRaw: firecrawlSourcesRaw,
                onChange: notifyCredentialsChanged
            ))
            .modifier(TavilyProviderObservers(
                tavilySearchDepth: tavilySearchDepth,
                tavilyTopic: tavilyTopic,
                tavilyCountry: tavilyCountry,
                tavilyAutoParameters: tavilyAutoParameters,
                onChange: notifyCredentialsChanged
            ))
            .modifier(PerplexityProviderObservers(
                perplexityCountry: perplexityCountry,
                perplexityLanguage: perplexityLanguage,
                onChange: notifyCredentialsChanged
            ))
            .onAppear {
                initializeCredentialEditorProviderIfNeeded()
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
    }

    private var formContent: some View {
        JinSettingsPage {
            JinSettingsToggleRow("Enable Web Search", isOn: $pluginEnabled)

            defaultsSection

            providerCredentialsSection

            JinSettingsSection("\(defaultProvider.displayName) Options") {
                providerAdvancedContent()
            }
        }
        .navigationTitle("Web Search")
    }

    private var defaultsSection: some View {
        JinSettingsSection("Search Defaults") {
            JinSettingsPickerRow(
                "Default search provider",
                selection: $defaultProviderRaw
            ) {
                ForEach(SearchPluginProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            JinSettingsControlRow("Default max results") {
                Stepper(
                    value: Binding(
                        get: { effectiveDefaultMaxResults },
                        set: { defaultMaxResults = WebSearchPluginSettingsSupport.effectiveMaxResults($0) }
                    ),
                    in: 1...50
                ) {
                    Text("\(effectiveDefaultMaxResults) results")
                }
            }

            JinSettingsPickerRow("Default recency", selection: $defaultRecencyDays) {
                ForEach(WebSearchPluginSettingsSupport.recencyChoices) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
        }
    }

    private var providerCredentialsSection: some View {
        JinSettingsSection("Search Providers") {
            JinSettingsPickerRow("Provider", selection: $credentialEditorProviderRaw) {
                ForEach(SearchPluginProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            WebSearchAPIKeyRow(
                label: "\(credentialEditorProvider.displayName) API Key",
                text: apiKeyBinding(for: credentialEditorProvider),
                isRevealed: keyVisibilityBinding(for: credentialEditorProvider),
                onClear: {
                    apiKeyBinding(for: credentialEditorProvider).wrappedValue = ""
                    keyVisibilityBinding(for: credentialEditorProvider).wrappedValue = false
                }
            )

            if let signupURL = credentialEditorProvider.signupURL {
                Link("Get an API key on \(credentialEditorProvider.displayName)", destination: signupURL)
                    .font(.caption)
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
            firecrawlLanguage: $firecrawlLanguage,
            firecrawlSourcesRaw: $firecrawlSourcesRaw,
            tavilySearchDepth: $tavilySearchDepth,
            tavilyTopic: $tavilyTopic,
            tavilyCountry: $tavilyCountry,
            tavilyAutoParameters: $tavilyAutoParameters,
            perplexityCountry: $perplexityCountry,
            perplexityLanguage: $perplexityLanguage
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
        }
    }

    private func initializeCredentialEditorProviderIfNeeded() {
        guard !hasInitializedCredentialEditorProvider else { return }
        hasInitializedCredentialEditorProvider = true

        credentialEditorProviderRaw = WebSearchPluginSettingsSupport.initialCredentialEditorProvider(
            configuredProviders: configuredProviders,
            defaultProvider: defaultProvider
        ).rawValue
    }

    private func notifyCredentialsChanged() {
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }
}
