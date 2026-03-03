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

    private let recencyChoices: [(label: String, value: Int)] = [
        ("Any time", 0),
        ("Past day", 1),
        ("Past week", 7),
        ("Past month", 30)
    ]

    private var defaultProvider: SearchPluginProvider {
        SearchPluginProvider(rawValue: defaultProviderRaw) ?? .exa
    }

    private var configuredProviderBadges: [String] {
        var out: [String] = []
        if !exaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(SearchPluginProvider.exa.displayName) }
        if !braveAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(SearchPluginProvider.brave.displayName) }
        if !jinaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(SearchPluginProvider.jina.displayName) }
        if !firecrawlAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(SearchPluginProvider.firecrawl.displayName) }
        if !tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(SearchPluginProvider.tavily.displayName) }
        return out
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
    }

    private var formContent: some View {
        Form {
            Section("Built-in Web Search") {
                Toggle("Enable plugin", isOn: $pluginEnabled)
            }

            defaultsSection

            apiKeysSection

            Section("Provider Advanced") {
                providerAdvancedContent()
            }

            Section("Configured Providers") {
                configuredProvidersContent
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

    private var apiKeysSection: some View {
        Section("API Keys") {
            apiKeyRow(label: "Exa API Key", text: $exaAPIKey, isVisible: $isExaKeyVisible)
            apiKeyRow(label: "Brave API Key", text: $braveAPIKey, isVisible: $isBraveKeyVisible)
            apiKeyRow(label: "Jina API Key", text: $jinaAPIKey, isVisible: $isJinaKeyVisible)
            apiKeyRow(label: "Firecrawl API Key", text: $firecrawlAPIKey, isVisible: $isFirecrawlKeyVisible)
            apiKeyRow(label: "Tavily API Key", text: $tavilyAPIKey, isVisible: $isTavilyKeyVisible)

        }
    }

    private func apiKeyRow(label: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(label, text: text)
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
    private var configuredProvidersContent: some View {
        if configuredProviderBadges.isEmpty {
            Text("No provider keys set yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(configuredProviderBadges.joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
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
        }
    }

    private func notifyCredentialsChanged() {
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }
}
