import SwiftUI

struct ContextCacheBasicsCard: View {
    @Binding var draft: ContextCacheControls

    let supportsExplicitMode: Bool
    let supportsStrategy: Bool

    var body: some View {
        JinSettingsCard {
            cardHeader
            modeRow
            strategyRow
            cachedContentNameRow
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text("Basics")
                .font(.headline)

            Spacer()

            Text(draft.mode.displayName)
                .jinTagStyle(foreground: draft.mode == .off ? .secondary : .accentColor)
        }
    }

    private var modeRow: some View {
        JinFormFieldRow("Mode") {
            JinSettingsSegmentedPicker("Mode", selection: $draft.mode, maxWidth: 380) {
                Text("Off").tag(ContextCacheMode.off)
                Text("Implicit").tag(ContextCacheMode.implicit)
                if supportsExplicitMode {
                    Text("Explicit").tag(ContextCacheMode.explicit)
                }
            }
        }
    }

    @ViewBuilder
    private var strategyRow: some View {
        if supportsStrategy, draft.mode != .off {
            JinFormFieldRow("Strategy", supportingText: "Anthropic only.") {
                JinSettingsMenuPicker("Strategy", selection: strategyBinding, maxWidth: 260) {
                    Text("System only").tag(ContextCacheStrategy.systemOnly)
                    Text("System + tools").tag(ContextCacheStrategy.systemAndTools)
                    Text("Prefix window").tag(ContextCacheStrategy.prefixWindow)
                }
            }
        }
    }

    @ViewBuilder
    private var cachedContentNameRow: some View {
        if supportsExplicitMode, draft.mode == .explicit {
            JinFormFieldRow("Cached content name", supportingText: "Example: cachedContents/project-brief-v2") {
                JinSettingsTextField(
                    "cachedContents/project-brief-v2",
                    text: cachedContentNameBinding,
                    usesMonospacedFont: true
                )
            }
        }
    }

    private var strategyBinding: Binding<ContextCacheStrategy> {
        Binding(
            get: { draft.strategy ?? .systemOnly },
            set: { draft.strategy = $0 }
        )
    }

    private var cachedContentNameBinding: Binding<String> {
        Binding(
            get: { draft.cachedContentName ?? "" },
            set: { draft.cachedContentName = $0 }
        )
    }
}

struct ContextCacheAdvancedCard: View {
    @Binding var draft: ContextCacheControls
    @Binding var ttlPreset: ContextCacheTTLPreset
    @Binding var customTTLDraft: String
    @Binding var minTokensDraft: String
    @Binding var advancedExpanded: Bool

    let providerType: ProviderType?
    let supportsTTL: Bool

    var body: some View {
        JinSettingsCard {
            DisclosureGroup(isExpanded: $advancedExpanded) {
                advancedContent
            } label: {
                advancedLabel
            }
        }
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if supportsTTL {
                ttlSection
            }

            if providerType == .xai || providerType == .openai {
                cacheKeySection
            }

            if providerType == .xai {
                minTokensSection
                conversationIDSection
            }
        }
        .padding(.top, JinSpacing.small)
    }

    private var advancedLabel: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text("Advanced")
                .font(.headline)

            Spacer(minLength: 0)

            Text("Optional")
                .jinTagStyle()
        }
    }

    private var ttlSection: some View {
        JinFormFieldRow("TTL") {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                JinSettingsMenuPicker("TTL", selection: $ttlPreset, maxWidth: 260) {
                    Text("Provider default").tag(ContextCacheTTLPreset.providerDefault)
                    Text("5 minutes").tag(ContextCacheTTLPreset.minutes5)
                    Text("1 hour").tag(ContextCacheTTLPreset.hour1)
                    Text("Custom").tag(ContextCacheTTLPreset.custom)
                }

                if ttlPreset == .custom {
                    JinSettingsTextField(
                        "Custom TTL seconds",
                        text: $customTTLDraft,
                        usesMonospacedFont: true
                    )
                        .frame(maxWidth: 220, alignment: .leading)
                }
            }
        }
    }

    private var cacheKeySection: some View {
        JinFormFieldRow("Cache key", supportingText: "Optional stable key.") {
            JinSettingsTextField(
                "stable-prefix-key",
                text: Binding(
                    get: { draft.cacheKey ?? "" },
                    set: { draft.cacheKey = $0 }
                ),
                usesMonospacedFont: true
            )
        }
    }

    private var minTokensSection: some View {
        JinFormFieldRow("Min tokens threshold", supportingText: "Optional.") {
            JinSettingsTextField("1024", text: $minTokensDraft, usesMonospacedFont: true)
                .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var conversationIDSection: some View {
        JinFormFieldRow("Conversation ID", supportingText: "Optional xAI scope.") {
            JinSettingsTextField(
                "x-grok-conv-id",
                text: Binding(
                    get: { draft.conversationID ?? "" },
                    set: { draft.conversationID = $0 }
                ),
                usesMonospacedFont: true
            )
        }
    }
}

struct ContextCacheFooterCard: View {
    let draftError: String?
    let summaryText: String
    let guidanceText: String

    var body: some View {
        JinSettingsSheetFooter(draftError: draftError) {
            JinSettingsFooterText(summaryText)
            JinSettingsFooterText(guidanceText)
        }
    }
}
