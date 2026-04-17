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
                    basicsCard

                    if supportsAdvancedOptions, draft.mode != .off {
                        advancedCard
                    }

                    footerCard
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

    // MARK: - Basics Card

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            HStack(alignment: .center, spacing: JinSpacing.small) {
                Text("Basics")
                    .font(.headline)
                Spacer()
                Text(draft.mode.displayName)
                    .jinTagStyle(foreground: draft.mode == .off ? .secondary : .accentColor)
            }

            JinFormFieldRow("Mode") {
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
                JinFormFieldRow("Strategy", supportingText: "Anthropic only.") {
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
                JinFormFieldRow("Cached content name", supportingText: "Example: cachedContents/project-brief-v2") {
                    TextField("cachedContents/project-brief-v2", text: Binding(
                        get: { draft.cachedContentName ?? "" },
                        set: { draft.cachedContentName = $0 }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }
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

                if providerType == .xai || providerType == .openai {
                    cacheKeySection
                }

                if providerType == .xai {
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
        JinFormFieldRow("TTL") {
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
        JinFormFieldRow("Cache key", supportingText: "Optional stable key.") {
            TextField("stable-prefix-key", text: Binding(
                get: { draft.cacheKey ?? "" },
                set: { draft.cacheKey = $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var minTokensSection: some View {
        JinFormFieldRow("Min tokens threshold", supportingText: "Optional.") {
            TextField("1024", text: $minTokensDraft)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var conversationIDSection: some View {
        JinFormFieldRow("Conversation ID", supportingText: "Optional xAI scope.") {
            TextField("x-grok-conv-id", text: Binding(
                get: { draft.conversationID ?? "" },
                set: { draft.conversationID = $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if let draftError {
                Text(draftError)
                    .jinInlineErrorText()
                    .padding(.horizontal, JinSpacing.small)
                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
            }

            JinDetailsDisclosure {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(guidanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
