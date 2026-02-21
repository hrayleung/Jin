import SwiftUI

struct ContextCacheSheetView: View {
    @Binding var draft: ContextCacheControls
    @Binding var ttlPreset: ContextCacheTTLPreset
    @Binding var customTTLDraft: String
    @Binding var minTokensDraft: String
    @Binding var advancedExpanded: Bool
    @Binding var draftError: String?

    let providerType: ProviderType?
    let supportsExplicitMode: Bool
    let supportsStrategy: Bool
    let supportsTTL: Bool
    let supportsAdvancedOptions: Bool
    let summaryText: String
    let guidanceText: String
    let isValid: Bool

    var onCancel: () -> Void
    var onSave: () -> Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    summaryCard
                    basicsCard

                    if supportsAdvancedOptions, draft.mode != .off {
                        advancedCard
                    }

                    if let draftError {
                        Text(draftError)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(JinSpacing.small)
                            .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                    } else {
                        Text(guidanceText)
                            .jinInfoCallout()
                    }
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Context Cache")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave() {
                            onCancel()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .center, spacing: JinSpacing.small) {
                Text("Current mode")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(draft.mode.displayName)
                    .jinTagStyle(foreground: draft.mode == .off ? .secondary : .accentColor)
            }

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    // MARK: - Basics Card

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text("Basics")
                .font(.headline)

            fieldRow(
                "Mode",
                hint: "Implicit works for OpenAI, Anthropic, and xAI. Gemini/Vertex can also use Explicit mode with a cached content resource."
            ) {
                Picker("Mode", selection: $draft.mode) {
                    Text("Off").tag(ContextCacheMode.off)
                    Text("Implicit").tag(ContextCacheMode.implicit)
                    if supportsExplicitMode {
                        Text("Explicit").tag(ContextCacheMode.explicit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
            }

            if supportsStrategy, draft.mode != .off {
                fieldRow(
                    "Strategy",
                    hint: "Anthropic only. Controls which stable prompt prefix is marked cacheable."
                ) {
                    Picker("Strategy", selection: Binding(
                        get: { draft.strategy ?? .systemOnly },
                        set: { draft.strategy = $0 }
                    )) {
                        Text("System only").tag(ContextCacheStrategy.systemOnly)
                        Text("System + tools").tag(ContextCacheStrategy.systemAndTools)
                        Text("Prefix window").tag(ContextCacheStrategy.prefixWindow)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260, alignment: .leading)
                }
            }

            if supportsExplicitMode, draft.mode == .explicit {
                fieldRow(
                    "Cached content name",
                    hint: "Gemini/Vertex resource name. Example: cachedContents/project-brief-v2"
                ) {
                    TextField("cachedContents/project-brief-v2", text: Binding(
                        get: { draft.cachedContentName ?? "" },
                        set: { draft.cachedContentName = $0 }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if draft.mode == .off {
                Text("Turn on Implicit or Explicit mode to configure caching options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    // MARK: - Advanced Card

    private var advancedCard: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                if supportsTTL {
                    ttlSection
                }

                if providerType == .openai || providerType == .xai {
                    cacheKeySection
                    minTokensSection
                }

                if providerType == .xai {
                    conversationIDSection
                }
            }
            .padding(.top, JinSpacing.small)
        } label: {
            HStack(alignment: .center, spacing: JinSpacing.small) {
                Text("Advanced")
                    .font(.headline)
                Spacer(minLength: 0)
                Text("Optional")
                    .jinTagStyle()
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    // MARK: - Advanced Sections

    private var ttlSection: some View {
        fieldRow(
            "TTL",
            hint: "OpenAI, Anthropic, and xAI support cache retention hints."
        ) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Picker("TTL", selection: $ttlPreset) {
                    Text("Provider default").tag(ContextCacheTTLPreset.providerDefault)
                    Text("5 minutes").tag(ContextCacheTTLPreset.minutes5)
                    Text("1 hour").tag(ContextCacheTTLPreset.hour1)
                    Text("Custom").tag(ContextCacheTTLPreset.custom)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260, alignment: .leading)

                if ttlPreset == .custom {
                    TextField("Custom TTL seconds", text: $customTTLDraft)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220, alignment: .leading)
                }
            }
        }
    }

    private var cacheKeySection: some View {
        fieldRow(
            "Cache key",
            hint: "Optional stable key for request prefixes that should map to the same cache."
        ) {
            TextField("stable-prefix-key", text: Binding(
                get: { draft.cacheKey ?? "" },
                set: { draft.cacheKey = $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var minTokensSection: some View {
        fieldRow(
            "Min tokens threshold",
            hint: "Optional. Cache hints apply only when prompt tokens are above this value."
        ) {
            TextField("1024", text: $minTokensDraft)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var conversationIDSection: some View {
        fieldRow(
            "Conversation ID",
            hint: "Optional xAI conversation scope for cache continuity."
        ) {
            TextField("x-grok-conv-id", text: Binding(
                get: { draft.conversationID ?? "" },
                set: { draft.conversationID = $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Reusable Field Layout

    @ViewBuilder
    private func fieldRow<Control: View>(
        _ title: String,
        hint: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - TTL Preset Enum

enum ContextCacheTTLPreset: String, CaseIterable {
    case providerDefault
    case minutes5
    case hour1
    case custom

    static func from(ttl: ContextCacheTTL?) -> ContextCacheTTLPreset {
        switch ttl {
        case .minutes5:
            return .minutes5
        case .hour1:
            return .hour1
        case .customSeconds:
            return .custom
        case .providerDefault, .none:
            return .providerDefault
        }
    }
}
