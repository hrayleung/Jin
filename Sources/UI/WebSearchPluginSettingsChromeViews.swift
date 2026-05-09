import SwiftUI

struct WebSearchAPIKeyRow: View {
    let label: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    let onClear: () -> Void

    var body: some View {
        JinSettingsControlRow(label) {
            HStack(spacing: JinSpacing.small) {
                JinRevealableSecureField(
                    title: label,
                    text: $text,
                    isRevealed: $isRevealed,
                    usesMonospacedFont: true,
                    revealHelp: "Show API key",
                    concealHelp: "Hide API key"
                )

                if !text.isEmpty {
                    Button("Clear", role: .destructive, action: onClear)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
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
        JinSettingsPickerRow("Search type", selection: $exaSearchTypeRaw) {
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
            fieldTitle: "e.g. US",
            text: $braveCountry,
            usesMonospacedFont: true
        )
    }

    private var braveLanguageRow: some View {
        JinSettingsTextFieldRow(
            "Language",
            fieldTitle: "e.g. en",
            text: $braveLanguage,
            usesMonospacedFont: true
        )
    }

    private var braveSafesearchRow: some View {
        JinSettingsPickerRow("Safesearch", selection: $braveSafesearch) {
            Text("Provider default").tag("")
            Text("Off").tag("off")
            Text("Moderate").tag("moderate")
            Text("Strict").tag("strict")
        }
    }

    private var jinaSettings: some View {
        JinSettingsToggleRow("Fetch pages with Jina Reader", isOn: $jinaReadPages)
    }

    private var firecrawlSettings: some View {
        JinSettingsToggleRow("Extract markdown content", isOn: $firecrawlExtractContent)
    }

    @ViewBuilder
    private var tavilySettings: some View {
        tavilySearchDepthRow
        tavilyTopicRow
    }

    private var tavilySearchDepthRow: some View {
        JinSettingsPickerRow("Search depth", selection: $tavilySearchDepth) {
            Text("Basic").tag("basic")
            Text("Fast").tag("fast")
            Text("Advanced").tag("advanced")
            Text("Ultra-fast").tag("ultra-fast")
        }
    }

    private var tavilyTopicRow: some View {
        JinSettingsPickerRow("Topic", selection: $tavilyTopic) {
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
