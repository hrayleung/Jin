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
        Form {
            Section("Built-in Web Search") {
                Toggle("Enable plugin", isOn: $pluginEnabled)
            }

            defaultsSection

            providerCredentialsSection

            Section("Provider Advanced") {
                providerAdvancedContent()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .navigationTitle("Web Search")
    }

    private var defaultsSection: some View {
        Section("Defaults") {
            Picker("Default provider", selection: $defaultProviderRaw) {
                ForEach(SearchPluginProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            Stepper(
                value: Binding(
                    get: { max(1, min(50, defaultMaxResults == 0 ? 8 : defaultMaxResults)) },
                    set: { defaultMaxResults = max(1, min(50, $0)) }
                ),
                in: 1...50
            ) {
                Text("Default max results: \(max(1, min(50, defaultMaxResults == 0 ? 8 : defaultMaxResults)))")
            }

            Picker("Default recency", selection: $defaultRecencyDays) {
                ForEach(recencyChoices, id: \.value) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
        }
    }

    private var providerCredentialsSection: some View {
        Section("Provider Credentials") {
            Picker("Edit provider", selection: $credentialEditorProviderRaw) {
                ForEach(SearchPluginProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            apiKeyRow(
                label: "\(credentialEditorProvider.displayName) API Key",
                text: apiKeyBinding(for: credentialEditorProvider),
                isVisible: keyVisibilityBinding(for: credentialEditorProvider)
            )

            HStack(spacing: 8) {
                Text(apiKeyBinding(for: credentialEditorProvider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Not configured"
                    : "Configured"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if !apiKeyBinding(for: credentialEditorProvider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear", role: .destructive) {
                        apiKeyBinding(for: credentialEditorProvider).wrappedValue = ""
                        keyVisibilityBinding(for: credentialEditorProvider).wrappedValue = false
                    }
                    .font(.caption)
                }
            }

            Text("Only providers with configured API keys are available in chat.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Configured") {
                Text("\(configuredProviders.count)/\(SearchPluginProvider.allCases.count)")
                    .foregroundStyle(.secondary)
            }

            if !configuredProviders.isEmpty {
                Text(configuredProviders.map(\.displayName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func apiKeyRow(label: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(text: text, prompt: Text(label)) {
                        EmptyView()
                    }
                        .textContentType(.password)
                } else {
                    SecureField(label, text: text)
                        .textContentType(.password)
                }
            }
            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(isVisible.wrappedValue ? "Hide API key" : "Show API key")
            .disabled(text.wrappedValue.isEmpty)
        }
    }

    @ViewBuilder
    private func providerAdvancedContent() -> some View {
        switch defaultProvider {
        case .exa:
            Picker("Search type", selection: $exaSearchTypeRaw) {
                Text("Auto").tag("")
                ForEach(ExaSearchType.publicCases, id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value.rawValue)
                }
            }
        case .brave:
            TextField(text: $braveCountry, prompt: Text("Country (2-letter, optional)")) {
                EmptyView()
            }
            TextField(text: $braveLanguage, prompt: Text("Language (e.g. en, zh-hans)")) {
                EmptyView()
            }
            Picker("Safesearch", selection: $braveSafesearch) {
                Text("Provider default").tag("")
                Text("Off").tag("off")
                Text("Moderate").tag("moderate")
                Text("Strict").tag("strict")
            }
        case .jina:
            Toggle("Fetch pages with Jina Reader", isOn: $jinaReadPages)
        case .firecrawl:
            Toggle("Extract markdown content", isOn: $firecrawlExtractContent)
        case .tavily:
            Picker("Search depth", selection: $tavilySearchDepth) {
                Text("Basic (1 credit)").tag("basic")
                Text("Fast (1 credit)").tag("fast")
                Text("Advanced (2 credits)").tag("advanced")
                Text("Ultra-fast (2 credits)").tag("ultra-fast")
            }
            Picker("Topic", selection: $tavilyTopic) {
                Text("General").tag("general")
                Text("News").tag("news")
                Text("Finance").tag("finance")
            }
        case .perplexity:
            Text("Perplexity Search currently has no plugin-specific options.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
