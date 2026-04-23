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
    @AppStorage(AppPreferenceKeys.pluginWebSearchBraveCountry) private var braveCountry = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchBraveLanguage) private var braveLanguage = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchBraveSafesearch) private var braveSafesearch = ""
    @AppStorage(AppPreferenceKeys.pluginWebSearchJinaReadPages) private var jinaReadPages = true
    @AppStorage(AppPreferenceKeys.pluginWebSearchFirecrawlExtractContent) private var firecrawlExtractContent = true
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilySearchDepth) private var tavilySearchDepth = "basic"
    @AppStorage(AppPreferenceKeys.pluginWebSearchTavilyTopic) private var tavilyTopic = "general"

    @State private var isExaKeyVisible = false
    @State private var isBraveKeyVisible = false
    @State private var isJinaKeyVisible = false
    @State private var isFirecrawlKeyVisible = false
    @State private var isTavilyKeyVisible = false
    @State private var isPerplexityKeyVisible = false
    @State private var credentialEditorProviderRaw = SearchPluginProvider.exa.rawValue
    @State private var hasInitializedCredentialEditorProvider = false

    private let recencyChoices: [(label: String, value: Int)] = [
        ("Any time", 0),
        ("Past day", 1),
        ("Past week", 7),
        ("Past month", 30)
    ]

    private var defaultProvider: SearchPluginProvider {
        SearchPluginProvider(rawValue: defaultProviderRaw) ?? .exa
    }

    private var credentialEditorProvider: SearchPluginProvider {
        SearchPluginProvider(rawValue: credentialEditorProviderRaw) ?? .exa
    }

    private var configuredProviders: [SearchPluginProvider] {
        SearchPluginProvider.allCases.filter { provider in
            !apiKeyBinding(for: provider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var effectiveDefaultMaxResults: Int {
        max(1, min(50, defaultMaxResults == 0 ? 8 : defaultMaxResults))
    }

    var body: some View {
        formContentWithAPIKeyObservers
            .onChange(of: exaSearchTypeRaw) { _, _ in notifyCredentialsChanged() }
            .onChange(of: braveCountry) { _, _ in notifyCredentialsChanged() }
            .onChange(of: braveLanguage) { _, _ in notifyCredentialsChanged() }
            .onChange(of: braveSafesearch) { _, _ in notifyCredentialsChanged() }
            .onChange(of: jinaReadPages) { _, _ in notifyCredentialsChanged() }
            .onChange(of: firecrawlExtractContent) { _, _ in notifyCredentialsChanged() }
            .onChange(of: tavilySearchDepth) { _, _ in notifyCredentialsChanged() }
            .onChange(of: tavilyTopic) { _, _ in notifyCredentialsChanged() }
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
            JinSettingsSection("Web Search") {
                Toggle("Enable Web Search", isOn: $pluginEnabled)
            }

            defaultsSection

            providerCredentialsSection

            JinSettingsSection(
                "Provider Settings",
                detail: "These options apply to the current default provider."
            ) {
                providerAdvancedContent()
            }
        }
        .navigationTitle("Web Search")
    }

    private var defaultsSection: some View {
        JinSettingsSection("Search Defaults") {
            settingsPickerRow(
                "Default search provider",
                supportingText: "Used when chat does not explicitly choose a web search provider.",
                selection: $defaultProviderRaw
            ) {
                ForEach(SearchPluginProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            JinSettingsControlRow(
                "Default max results",
                supportingText: "Applies to web searches unless a request overrides the limit."
            ) {
                Stepper(
                    value: Binding(
                        get: { effectiveDefaultMaxResults },
                        set: { defaultMaxResults = max(1, min(50, $0)) }
                    ),
                    in: 1...50
                ) {
                    Text("\(effectiveDefaultMaxResults) results")
                }
            }

            settingsPickerRow(
                "Default recency",
                supportingText: "Filters for recent content when the selected provider supports recency windows.",
                selection: $defaultRecencyDays
            ) {
                ForEach(recencyChoices, id: \.value) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
        }
    }

    private var providerCredentialsSection: some View {
        JinSettingsSection(
            "Search Providers",
            detail: "Only providers with configured API keys are available in chat."
        ) {
            settingsPickerRow(
                "Provider",
                supportingText: "Choose which provider you want to edit.",
                selection: $credentialEditorProviderRaw
            ) {
                ForEach(SearchPluginProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            apiKeyRow(
                label: "\(credentialEditorProvider.displayName) API Key",
                text: apiKeyBinding(for: credentialEditorProvider),
                isVisible: keyVisibilityBinding(for: credentialEditorProvider)
            )

            JinSettingsControlRow(
                "Status",
                supportingText: "Clearing removes the stored key for the selected provider."
            ) {
                HStack(spacing: JinSpacing.small) {
                    Text(apiKeyBinding(for: credentialEditorProvider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Not configured"
                        : "Configured"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: JinSpacing.small)

                    if !apiKeyBinding(for: credentialEditorProvider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Clear", role: .destructive) {
                            apiKeyBinding(for: credentialEditorProvider).wrappedValue = ""
                            keyVisibilityBinding(for: credentialEditorProvider).wrappedValue = false
                        }
                        .font(.caption)
                        .help("Clear the stored API key for \(credentialEditorProvider.displayName).")
                    }
                }
            }

            JinSettingsControlRow(
                "Configured",
                supportingText: "Only configured providers appear in chat."
            ) {
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    Text("\(configuredProviders.count)/\(SearchPluginProvider.allCases.count)")
                        .foregroundStyle(.secondary)

                    if !configuredProviders.isEmpty {
                        Text(configuredProviders.map(\.displayName).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func apiKeyRow(label: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        JinSettingsControlRow(
            label,
            supportingText: "Leave blank to keep this provider unavailable in chat."
        ) {
            JinRevealableSecureField(
                title: label,
                text: text,
                isRevealed: isVisible,
                usesMonospacedFont: true,
                revealHelp: "Show API key",
                concealHelp: "Hide API key"
            )
        }
    }

    @ViewBuilder
    private func providerAdvancedContent() -> some View {
        switch defaultProvider {
        case .exa:
            settingsPickerRow(
                "Search type",
                supportingText: "Auto works well for most queries. Pick a type only when you need a stronger bias.",
                selection: $exaSearchTypeRaw
            ) {
                Text("Auto").tag("")
                ForEach(ExaSearchType.publicCases, id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value.rawValue)
                }
            }
        case .brave:
            JinSettingsControlRow(
                "Country",
                supportingText: "Optional 2-letter country code such as US, SG, or DE."
            ) {
                TextField("Country", text: $braveCountry, prompt: Text("Country (2-letter, optional)"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            JinSettingsControlRow(
                "Language",
                supportingText: "Optional language hint such as en or zh-hans."
            ) {
                TextField("Language", text: $braveLanguage, prompt: Text("Language (e.g. en, zh-hans)"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            settingsPickerRow(
                "Safesearch",
                supportingText: "Uses Brave's provider-side safe search filter.",
                selection: $braveSafesearch
            ) {
                Text("Provider default").tag("")
                Text("Off").tag("off")
                Text("Moderate").tag("moderate")
                Text("Strict").tag("strict")
            }
        case .jina:
            JinSettingsControlRow(
                "Fetch pages with Jina Reader",
                supportingText: "Requests Jina Reader content for pages before sending results back to chat."
            ) {
                Toggle("Fetch pages with Jina Reader", isOn: $jinaReadPages)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .firecrawl:
            JinSettingsControlRow(
                "Extract markdown content",
                supportingText: "When enabled, Firecrawl returns extracted page content instead of just the search hit."
            ) {
                Toggle("Extract markdown content", isOn: $firecrawlExtractContent)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .tavily:
            settingsPickerRow(
                "Search depth",
                supportingText: "Deeper searches can improve coverage but may consume more credits.",
                selection: $tavilySearchDepth
            ) {
                Text("Basic (1 credit)").tag("basic")
                Text("Fast (1 credit)").tag("fast")
                Text("Advanced (2 credits)").tag("advanced")
                Text("Ultra-fast (2 credits)").tag("ultra-fast")
            }

            settingsPickerRow(
                "Topic",
                supportingText: "Choose a topic hint when you want results tuned for a specific domain.",
                selection: $tavilyTopic
            ) {
                Text("General").tag("general")
                Text("News").tag("news")
                Text("Finance").tag("finance")
            }
        case .perplexity:
            Text("Perplexity Search currently has no plugin-specific options.")
                .jinInfoCallout()
        }
    }

    private func settingsPickerRow<SelectionValue: Hashable, Content: View>(
        _ title: String,
        supportingText: String? = nil,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        JinSettingsControlRow(title, supportingText: supportingText) {
            Picker(title, selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

        if let firstConfigured = configuredProviders.first {
            credentialEditorProviderRaw = firstConfigured.rawValue
            return
        }
        credentialEditorProviderRaw = defaultProvider.rawValue
    }

    private func notifyCredentialsChanged() {
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }
}
