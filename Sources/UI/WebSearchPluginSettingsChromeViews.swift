import SwiftUI

struct WebSearchAPIKeyRow: View {
    let label: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    let onClear: () -> Void

    var body: some View {
        JinSettingsControlRow(label, controlAlignment: .leading) {
            HStack(spacing: JinSpacing.small) {
                JinRevealableSecureField(
                    prompt: "",
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
    @Binding var firecrawlSourcesRaw: String

    @Binding var tavilySearchDepth: String
    @Binding var tavilyTopic: String
    @Binding var tavilyCountry: String
    @Binding var tavilyAutoParameters: Bool

    @Binding var perplexityCountry: String
    @Binding var perplexityLanguage: String

    @Binding var tinyfishLocation: String
    @Binding var tinyfishLanguage: String
    @Binding var tinyfishDomainTypeRaw: String
    @Binding var tinyfishFetchPages: Bool

    @Binding var firecrawlLocation: String
    @Binding var firecrawlSafe: Bool

    @Binding var tavilyLanguage: String
    @Binding var tavilyFilterByLanguage: Bool
    @Binding var tavilySafeSearch: Bool

    @Binding var parallelSearchModeRaw: String
    @Binding var parallelLocation: String
    @Binding var parallelExtractPages: Bool

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
        case .tinyfish:
            tinyfishSettings
        case .parallel:
            parallelSettings
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
            ForEach(ExaCategory.publicCases, id: \.self) { value in
                Text(exaCategoryLabel(for: value)).tag(value.rawValue)
            }
        }

        JinSettingsTextFieldRow(
            "User location",
            prompt: "e.g. US",
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
            prompt: "e.g. US",
            text: $braveCountry,
            usesMonospacedFont: true
        )
    }

    private var braveLanguageRow: some View {
        JinSettingsTextFieldRow(
            "Language",
            prompt: "e.g. en",
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
            prompt: "e.g. US",
            text: $jinaCountry,
            usesMonospacedFont: true
        )

        JinSettingsTextFieldRow(
            "Locale",
            prompt: "e.g. en-US",
            text: $jinaLocale,
            usesMonospacedFont: true
        )
    }

    @ViewBuilder
    private var firecrawlSettings: some View {
        JinSettingsToggleRow("Extract markdown content", isOn: $firecrawlExtractContent)

        JinSettingsTextFieldRow(
            "Country",
            prompt: "e.g. US",
            text: $firecrawlCountry,
            usesMonospacedFont: true
        )

        JinSettingsTextFieldRow(
            "Location",
            prompt: "e.g. Germany",
            supportingText: "Geo-targeted results. Works best with Country.",
            text: $firecrawlLocation,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow("Filter unsafe content", isOn: $firecrawlSafe)

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
            prompt: "e.g. US",
            supportingText: "Applies on General topic only.",
            text: $tavilyCountry,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow(
            "Auto-tune parameters",
            supportingText: "Tavily may override depth and topic.",
            isOn: $tavilyAutoParameters
        )

        JinSettingsTextFieldRow(
            "Language",
            prompt: "e.g. en",
            supportingText: "ISO 639-1 code or English name. Boosts matching results.",
            text: $tavilyLanguage,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow(
            "Strict language filter",
            supportingText: "Drop results that do not match Language.",
            isOn: $tavilyFilterByLanguage
        )

        JinSettingsToggleRow(
            "Safe search",
            supportingText: "Not available for Fast or Ultra-fast depth.",
            isOn: $tavilySafeSearch
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
            prompt: "e.g. US",
            text: $perplexityCountry,
            usesMonospacedFont: true
        )

        JinSettingsTextFieldRow(
            "Language",
            prompt: "e.g. en",
            text: $perplexityLanguage,
            usesMonospacedFont: true
        )
    }

    @ViewBuilder
    private var tinyfishSettings: some View {
        JinSettingsPickerRow("Domain type", selection: $tinyfishDomainTypeRaw) {
            ForEach(TinyFishDomainType.allCases, id: \.self) { value in
                Text(value.displayName).tag(value == .web ? "" : value.rawValue)
            }
        }

        JinSettingsTextFieldRow(
            "Location",
            prompt: "e.g. US",
            supportingText: "ISO country code. Auto-resolves with Language.",
            text: $tinyfishLocation,
            usesMonospacedFont: true
        )

        JinSettingsTextFieldRow(
            "Language",
            prompt: "e.g. en",
            text: $tinyfishLanguage,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow(
            "Fetch page content",
            supportingText: "Read top result pages via TinyFish Fetch.",
            isOn: $tinyfishFetchPages
        )
    }

    @ViewBuilder
    private var parallelSettings: some View {
        JinSettingsPickerRow(
            "Search mode",
            supportingText: ParallelSearchMode.resolved(from: parallelSearchModeRaw)?.supportingText,
            selection: $parallelSearchModeRaw
        ) {
            ForEach(ParallelSearchMode.publicCases, id: \.self) { value in
                Text(parallelSearchModeLabel(for: value)).tag(value.rawValue)
            }
        }

        JinSettingsTextFieldRow(
            "Location",
            prompt: "e.g. US",
            supportingText: "ISO 3166-1 alpha-2 country code. Use GB for the United Kingdom.",
            text: $parallelLocation,
            usesMonospacedFont: true
        )

        JinSettingsToggleRow(
            "Extract result pages",
            supportingText: "Follow Search with Parallel Extract for richer markdown excerpts.",
            isOn: $parallelExtractPages
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
    let firecrawlLocation: String
    let firecrawlSafe: Bool
    let firecrawlSourcesRaw: String
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: firecrawlExtractContent) { _, _ in onChange() }
            .onChange(of: firecrawlCountry) { _, _ in onChange() }
            .onChange(of: firecrawlLocation) { _, _ in onChange() }
            .onChange(of: firecrawlSafe) { _, _ in onChange() }
            .onChange(of: firecrawlSourcesRaw) { _, _ in onChange() }
    }
}

struct TavilyProviderObservers: ViewModifier {
    let tavilySearchDepth: String
    let tavilyTopic: String
    let tavilyCountry: String
    let tavilyAutoParameters: Bool
    let tavilyLanguage: String
    let tavilyFilterByLanguage: Bool
    let tavilySafeSearch: Bool
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: tavilySearchDepth) { _, _ in onChange() }
            .onChange(of: tavilyTopic) { _, _ in onChange() }
            .onChange(of: tavilyCountry) { _, _ in onChange() }
            .onChange(of: tavilyAutoParameters) { _, _ in onChange() }
            .onChange(of: tavilyLanguage) { _, _ in onChange() }
            .onChange(of: tavilyFilterByLanguage) { _, _ in onChange() }
            .onChange(of: tavilySafeSearch) { _, _ in onChange() }
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

struct TinyFishProviderObservers: ViewModifier {
    let tinyfishLocation: String
    let tinyfishLanguage: String
    let tinyfishDomainTypeRaw: String
    let tinyfishFetchPages: Bool
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: tinyfishLocation) { _, _ in onChange() }
            .onChange(of: tinyfishLanguage) { _, _ in onChange() }
            .onChange(of: tinyfishDomainTypeRaw) { _, _ in onChange() }
            .onChange(of: tinyfishFetchPages) { _, _ in onChange() }
    }
}

struct ParallelProviderObservers: ViewModifier {
    let parallelSearchModeRaw: String
    let parallelLocation: String
    let parallelExtractPages: Bool
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: parallelSearchModeRaw) { _, _ in onChange() }
            .onChange(of: parallelLocation) { _, _ in onChange() }
            .onChange(of: parallelExtractPages) { _, _ in onChange() }
    }
}

private func parallelSearchModeLabel(for value: ParallelSearchMode) -> String {
    switch value {
    case .fast: return "Fast (recommended)"
    case .turbo, .basic, .advanced: return value.displayName
    }
}

private func exaSearchTypeLabel(for value: ExaSearchType) -> String {
    switch value {
    case .auto: return "Auto"
    case .fast: return "Fast"
    case .neural: return "Auto" // legacy case; not shown in publicCases
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
    case .publication: return "Research paper"
    case .news: return "News"
    case .personalSite: return "Personal site"
    case .financialReport: return "Financial report"
    case .people: return "People"
    }
}
