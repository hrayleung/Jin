import SwiftUI

struct WebSearchAPIKeyRow: View {
    let label: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    var body: some View {
        JinSettingsSecureFieldRow(
            label,
            supportingText: "Leave blank to keep this provider unavailable in chat.",
            text: $text,
            isRevealed: $isRevealed,
            usesMonospacedFont: true,
            revealHelp: "Show API key",
            concealHelp: "Hide API key"
        )
    }
}

struct WebSearchCredentialStatusRow: View {
    let provider: SearchPluginProvider
    let apiKey: String
    let onClear: () -> Void

    var body: some View {
        JinSettingsControlRow(
            "Status",
            supportingText: "Clearing removes the stored key for the selected provider."
        ) {
            HStack(spacing: JinSpacing.small) {
                Text(WebSearchPluginSettingsSupport.credentialStatusText(apiKey: apiKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: JinSpacing.small)

                if WebSearchPluginSettingsSupport.hasConfiguredCredential(apiKey) {
                    Button("Clear", role: .destructive) {
                        onClear()
                    }
                    .font(.caption)
                    .help("Clear the stored API key for \(provider.displayName).")
                }
            }
        }
    }
}

struct WebSearchConfiguredProvidersRow: View {
    let configuredProviders: [SearchPluginProvider]

    var body: some View {
        JinSettingsControlRow(
            "Configured",
            supportingText: "Only configured providers appear in chat."
        ) {
            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text(WebSearchPluginSettingsSupport.configuredCountText(configuredProviders))
                    .foregroundStyle(.secondary)

                let summary = WebSearchPluginSettingsSupport.configuredProviderNamesText(configuredProviders)
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct WebSearchAdvancedProviderSettingsView: View {
    let provider: SearchPluginProvider
    @Binding var exaSearchTypeRaw: String
    @Binding var braveCountry: String
    @Binding var braveLanguage: String
    @Binding var braveSafesearch: String
    @Binding var jinaReadPages: Bool
    @Binding var firecrawlExtractContent: Bool
    @Binding var tavilySearchDepth: String
    @Binding var tavilyTopic: String

    var body: some View {
        providerSettings
    }

    @ViewBuilder
    private var providerSettings: some View {
        switch provider {
        case .exa:
            exaSettings
        case .brave:
            braveSettings
        case .jina:
            jinaSettings
        case .firecrawl:
            firecrawlSettings
        case .tavily:
            tavilySettings
        case .perplexity:
            perplexitySettings
        }
    }

    private var exaSettings: some View {
        JinSettingsPickerRow(
            "Search type",
            supportingText: "Auto works well for most queries. Pick a type only when you need a stronger bias.",
            selection: $exaSearchTypeRaw
        ) {
            Text("Auto").tag("")
            ForEach(ExaSearchType.publicCases, id: \.self) { value in
                Text(value.rawValue.capitalized).tag(value.rawValue)
            }
        }
    }

    @ViewBuilder
    private var braveSettings: some View {
        braveCountryRow
        braveLanguageRow
        braveSafesearchRow
    }

    private var braveCountryRow: some View {
        JinSettingsTextFieldRow(
            "Country",
            fieldTitle: "Country",
            supportingText: "Optional 2-letter country code such as US, SG, or DE.",
            text: $braveCountry,
            usesMonospacedFont: true
        )
    }

    private var braveLanguageRow: some View {
        JinSettingsTextFieldRow(
            "Language",
            fieldTitle: "Language",
            supportingText: "Optional language hint such as en or zh-hans.",
            text: $braveLanguage,
            usesMonospacedFont: true
        )
    }

    private var braveSafesearchRow: some View {
        JinSettingsPickerRow(
            "Safesearch",
            supportingText: "Uses Brave's provider-side safe search filter.",
            selection: $braveSafesearch
        ) {
            Text("Provider default").tag("")
            Text("Off").tag("off")
            Text("Moderate").tag("moderate")
            Text("Strict").tag("strict")
        }
    }

    private var jinaSettings: some View {
        JinSettingsToggleRow(
            "Fetch pages with Jina Reader",
            supportingText: "Requests Jina Reader content for pages before sending results back to chat.",
            isOn: $jinaReadPages
        )
    }

    private var firecrawlSettings: some View {
        JinSettingsToggleRow(
            "Extract markdown content",
            supportingText: "When enabled, Firecrawl returns extracted page content instead of just the search hit.",
            isOn: $firecrawlExtractContent
        )
    }

    @ViewBuilder
    private var tavilySettings: some View {
        tavilySearchDepthRow
        tavilyTopicRow
    }

    private var tavilySearchDepthRow: some View {
        JinSettingsPickerRow(
            "Search depth",
            supportingText: "Deeper searches can improve coverage but may consume more credits.",
            selection: $tavilySearchDepth
        ) {
            Text("Basic (1 credit)").tag("basic")
            Text("Fast (1 credit)").tag("fast")
            Text("Advanced (2 credits)").tag("advanced")
            Text("Ultra-fast (2 credits)").tag("ultra-fast")
        }
    }

    private var tavilyTopicRow: some View {
        JinSettingsPickerRow(
            "Topic",
            supportingText: "Choose a topic hint when you want results tuned for a specific domain.",
            selection: $tavilyTopic
        ) {
            Text("General").tag("general")
            Text("News").tag("news")
            Text("Finance").tag("finance")
        }
    }

    private var perplexitySettings: some View {
        Text("Perplexity Search currently has no plugin-specific options.")
            .jinInfoCallout()
    }
}
