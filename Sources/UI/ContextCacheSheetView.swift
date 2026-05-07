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
                    ContextCacheBasicsCard(
                        draft: $draft,
                        supportsExplicitMode: supportsExplicitMode,
                        supportsStrategy: supportsStrategy
                    )

                    if supportsAdvancedOptions, draft.mode != .off {
                        ContextCacheAdvancedCard(
                            draft: $draft,
                            ttlPreset: $ttlPreset,
                            customTTLDraft: $customTTLDraft,
                            minTokensDraft: $minTokensDraft,
                            advancedExpanded: $advancedExpanded,
                            providerType: providerType,
                            supportsTTL: supportsTTL
                        )
                    }

                    ContextCacheFooterCard(
                        draftError: draftError,
                        summaryText: summaryText,
                        guidanceText: guidanceText
                    )
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
