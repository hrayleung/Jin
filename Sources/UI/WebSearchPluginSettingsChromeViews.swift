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
    @Binding var exaCategory: String
    @Binding var exaUserLocation: String
    @Binding var exaModeration: Bool

    @Binding var braveCountry: String
    @Binding var braveLanguage: String
    @Binding var braveSafesearch: String

    @Binding var jinaReadPages: Bool
    @Binding var jinaCountry: String
    @Binding var jinaLocale: String

    @Binding var firecrawlExtractContent: Bool
    @Binding var firecrawlCountry: String
    @Binding var firecrawlLanguage: String
    @Binding var firecrawlSourcesRaw: String

    @Binding var tavilySearchDepth: String
    @Binding var tavilyTopic: String
    @Binding var tavilyCountry: String
    @Binding var tavilyAutoParameters: Bool

    @Binding var perplexityCountry: String
    @Binding var perplexityLanguage: String

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

    @ViewBuilder
    private var exaSettings: some View {
        JinSettingsPickerRow("Search type", selection: $exaSearchTypeRaw) {
            Text("Auto").tag("")
            ForEach(ExaSearchType.publicCases, id: \.self) { value in
                Text(exaSearchTypeLabel(for: value)).tag(value.rawValue)
            }
        }

        JinSettingsPickerRow("Category", selection: $exaCategory) {
            Text("Any").tag("")
            ForEach(ExaCategory.allCases, id: \.self) { value in
                Text(exaCategoryLabel(for: value)).tag(value.rawValue)
            }
        }

        JinSettingsTextFieldRow(
            "User location",
            fieldTitle: "e.g. US",
            text: $exaUserLocation,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow("Filter unsafe content", isOn: $exaModeration)
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

    @ViewBuilder
    private var jinaSettings: some View {
        JinSettingsToggleRow("Fetch pages with Jina Reader", isOn: $jinaReadPages)

        JinSettingsTextFieldRow(
            "Country",
            fieldTitle: "e.g. US",
            text: $jinaCountry,
            usesMonospacedFont: true
        )

        JinSettingsTextFieldRow(
            "Locale",
            fieldTitle: "e.g. en-US",
            text: $jinaLocale,
            usesMonospacedFont: true
        )
    }

    @ViewBuilder
    private var firecrawlSettings: some View {
        JinSettingsToggleRow("Extract markdown content", isOn: $firecrawlExtractContent)

        JinSettingsTextFieldRow(
            "Country",
            fieldTitle: "e.g. US",
            text: $firecrawlCountry,
            usesMonospacedFont: true
        )

        JinSettingsTextFieldRow(
            "Language",
            fieldTitle: "e.g. en",
            text: $firecrawlLanguage,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow("Web results", isOn: firecrawlSourceBinding(for: .web))
        JinSettingsToggleRow("News results", isOn: firecrawlSourceBinding(for: .news))
        JinSettingsToggleRow("Image results", isOn: firecrawlSourceBinding(for: .images))
    }

    @ViewBuilder
    private var tavilySettings: some View {
        tavilySearchDepthRow
        tavilyTopicRow

        JinSettingsTextFieldRow(
            "Country",
            fieldTitle: "e.g. US",
            supportingText: "Applies on General topic only.",
            text: $tavilyCountry,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow(
            "Auto-tune parameters",
            supportingText: "Tavily may override depth and topic.",
            isOn: $tavilyAutoParameters
        )
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

    @ViewBuilder
    private var perplexitySettings: some View {
        JinSettingsTextFieldRow(
            "Country",
            fieldTitle: "e.g. US",
            text: $perplexityCountry,
            usesMonospacedFont: true
        )

        JinSettingsTextFieldRow(
            "Language",
            fieldTitle: "e.g. en",
            text: $perplexityLanguage,
            usesMonospacedFont: true
        )
    }

    // MARK: - Firecrawl sources binding

    private func firecrawlSourceBinding(for kind: FirecrawlSourceKind) -> Binding<Bool> {
        Binding(
            get: {
                firecrawlSelectedSources().contains(kind)
            },
            set: { isOn in
                var current = firecrawlSelectedSources()
                if isOn {
                    if !current.contains(kind) {
                        current.append(kind)
                    }
                } else {
                    current.removeAll { $0 == kind }
                }
                firecrawlSourcesRaw = WebSearchPluginSettingsStore.encodeFirecrawlSources(current)
            }
        )
    }

    private func firecrawlSelectedSources() -> [FirecrawlSourceKind] {
        WebSearchPluginSettingsStore.firecrawlSourceSelection(from: firecrawlSourcesRaw)
    }
}

// MARK: - Observers

/// Per-provider observer modifiers split out so the main view can chain them without the SwiftUI
/// type checker timing out (it could not handle 20+ `.onChange` modifiers in one expression).

struct ExaProviderObservers: ViewModifier {
    let exaSearchTypeRaw: String
    let exaCategory: String
    let exaUserLocation: String
    let exaModeration: Bool
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: exaSearchTypeRaw) { _, _ in onChange() }
            .onChange(of: exaCategory) { _, _ in onChange() }
            .onChange(of: exaUserLocation) { _, _ in onChange() }
            .onChange(of: exaModeration) { _, _ in onChange() }
    }
}

struct BraveProviderObservers: ViewModifier {
    let braveCountry: String
    let braveLanguage: String
    let braveSafesearch: String
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: braveCountry) { _, _ in onChange() }
            .onChange(of: braveLanguage) { _, _ in onChange() }
            .onChange(of: braveSafesearch) { _, _ in onChange() }
    }
}

struct JinaProviderObservers: ViewModifier {
    let jinaReadPages: Bool
    let jinaCountry: String
    let jinaLocale: String
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: jinaReadPages) { _, _ in onChange() }
            .onChange(of: jinaCountry) { _, _ in onChange() }
            .onChange(of: jinaLocale) { _, _ in onChange() }
    }
}

struct FirecrawlProviderObservers: ViewModifier {
    let firecrawlExtractContent: Bool
    let firecrawlCountry: String
    let firecrawlLanguage: String
    let firecrawlSourcesRaw: String
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: firecrawlExtractContent) { _, _ in onChange() }
            .onChange(of: firecrawlCountry) { _, _ in onChange() }
            .onChange(of: firecrawlLanguage) { _, _ in onChange() }
            .onChange(of: firecrawlSourcesRaw) { _, _ in onChange() }
    }
}

struct TavilyProviderObservers: ViewModifier {
    let tavilySearchDepth: String
    let tavilyTopic: String
    let tavilyCountry: String
    let tavilyAutoParameters: Bool
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: tavilySearchDepth) { _, _ in onChange() }
            .onChange(of: tavilyTopic) { _, _ in onChange() }
            .onChange(of: tavilyCountry) { _, _ in onChange() }
            .onChange(of: tavilyAutoParameters) { _, _ in onChange() }
    }
}

struct PerplexityProviderObservers: ViewModifier {
    let perplexityCountry: String
    let perplexityLanguage: String
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: perplexityCountry) { _, _ in onChange() }
            .onChange(of: perplexityLanguage) { _, _ in onChange() }
    }
}

private func exaSearchTypeLabel(for value: ExaSearchType) -> String {
    switch value {
    case .auto: return "Auto"
    case .fast: return "Fast"
    case .neural: return "Neural"
    case .deepLite: return "Deep Lite"
    case .deep: return "Deep"
    case .deepReasoning: return "Deep Reasoning"
    case .instant: return "Instant"
    }
}

private func exaCategoryLabel(for value: ExaCategory) -> String {
    switch value {
    case .company: return "Company"
    case .researchPaper: return "Research paper"
    case .news: return "News"
    case .personalSite: return "Personal site"
    case .financialReport: return "Financial report"
    case .people: return "People"
    }
}
