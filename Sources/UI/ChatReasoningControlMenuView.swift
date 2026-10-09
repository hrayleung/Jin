import SwiftUI

struct ReasoningControlMenuView: View {
    let reasoningConfig: ModelReasoningConfig?
    let supportsReasoningDisableToggle: Bool
    let isReasoningEnabled: Bool
    let isAnthropicProvider: Bool
    let supportsCerebrasPreservedThinkingToggle: Bool
    let cerebrasPreserveThinkingBinding: Binding<Bool>
    let availableReasoningEffortLevels: [ReasoningEffort]
    /// When true, effort labels describe multi-agent agent count rather than thinking depth.
    let usesXAIMultiAgentEffortLabels: Bool
    let supportsReasoningSummaryControl: Bool
    let currentReasoningSummary: ReasoningSummary
    let currentReasoningEffort: ReasoningEffort?
    let supportsProMode: Bool
    let isProModeEnabled: Bool
    let supportsReasoningContext: Bool
    let currentReasoningContext: ReasoningContextMode?
    let supportsTextVerbosity: Bool
    let currentTextVerbosity: TextVerbosity?
    let supportsFireworksReasoningHistoryToggle: Bool
    let fireworksReasoningHistoryOptions: [String]
    let fireworksReasoningHistory: String?
    let budgetTokensLabel: String
    let fireworksReasoningHistoryLabel: (String) -> String
    let onSetReasoningOff: () -> Void
    let onSetReasoningOn: () -> Void
    let onOpenThinkingBudgetEditor: () -> Void
    let onSetReasoningEffort: (ReasoningEffort) -> Void
    let onSetReasoningSummary: (ReasoningSummary) -> Void
    let onSetProMode: (Bool) -> Void
    let onSetReasoningContext: (ReasoningContextMode?) -> Void
    let onSetTextVerbosity: (TextVerbosity?) -> Void
    let onSetFireworksReasoningHistory: (String?) -> Void

    @ViewBuilder
    var body: some View {
        if let reasoningConfig, reasoningConfig.type != .none {
            if supportsReasoningDisableToggle {
                JinMenuSelectionItem(
                    "Off",
                    isSelected: ChatReasoningSupport.isReasoningOffMenuSelected(
                        isReasoningEnabled: isReasoningEnabled,
                        currentEffort: currentReasoningEffort,
                        includesDisableToggle: true
                    ),
                    action: onSetReasoningOff
                )
            }

            switch reasoningConfig.type {
            case .toggle:
                JinMenuSelectionItem("On", isSelected: isReasoningEnabled, action: onSetReasoningOn)

                if supportsCerebrasPreservedThinkingToggle {
                    Divider()
                    Toggle("Preserve thinking", isOn: cerebrasPreserveThinkingBinding)
                        .help("Keeps GLM thinking across turns (maps to clear_thinking: false).")
                }

            case .effort:
                if isAnthropicProvider {
                    JinMenuSelectionItem(
                        "Configure thinking…", isSelected: isReasoningEnabled, action: onOpenThinkingBudgetEditor
                    )
                } else {
                    ForEach(menuEffortLevels, id: \.self) { level in
                        JinMenuSelectionItem(
                            effortLabel(for: level),
                            isSelected: isReasoningEnabled && currentReasoningEffort == level
                        ) {
                            onSetReasoningEffort(level)
                        }
                    }
                }

                if !isAnthropicProvider && supportsReasoningSummaryControl {
                    Divider()
                    Text("Reasoning summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(ReasoningSummary.allCases, id: \.self) { summary in
                        JinMenuSelectionItem(
                            summary.displayName,
                            isSelected: currentReasoningSummary == summary
                        ) {
                            onSetReasoningSummary(summary)
                        }
                    }
                }

                if supportsProMode {
                    Divider()
                    Text("Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    JinMenuSelectionItem("Standard", isSelected: !isProModeEnabled) {
                        onSetProMode(false)
                    }
                    JinMenuSelectionItem("Pro", isSelected: isProModeEnabled) {
                        onSetProMode(true)
                    }
                    .help("Uses more model work for higher reliability (GPT-5.6 reasoning.mode=pro).")
                }

                if supportsReasoningContext {
                    Divider()
                    Text("Reasoning context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    JinMenuSelectionItem("Default", isSelected: currentReasoningContext == nil) {
                        onSetReasoningContext(nil)
                    }
                    ForEach(ReasoningContextMode.allCases, id: \.self) { mode in
                        JinMenuSelectionItem(mode.displayName, isSelected: currentReasoningContext == mode) {
                            onSetReasoningContext(mode)
                        }
                    }
                    .help("Controls multi-turn reuse of prior reasoning items (Responses API reasoning.context).")
                }

                if supportsTextVerbosity {
                    Divider()
                    Text("Verbosity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    JinMenuSelectionItem("Default", isSelected: currentTextVerbosity == nil) {
                        onSetTextVerbosity(nil)
                    }
                    ForEach(TextVerbosity.allCases, id: \.self) { level in
                        JinMenuSelectionItem(level.displayName, isSelected: currentTextVerbosity == level) {
                            onSetTextVerbosity(level)
                        }
                    }
                }

                if supportsFireworksReasoningHistoryToggle {
                    Divider()
                    Text("Thinking history")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    JinMenuSelectionItem("Default (model)", isSelected: fireworksReasoningHistory == nil) {
                        onSetFireworksReasoningHistory(nil)
                    }

                    ForEach(fireworksReasoningHistoryOptions, id: \.self) { option in
                        JinMenuSelectionItem(
                            fireworksReasoningHistoryLabel(option),
                            isSelected: fireworksReasoningHistory == option
                        ) {
                            onSetFireworksReasoningHistory(option)
                        }
                    }
                }

            case .budget:
                JinMenuSelectionItem(
                    "Budget tokens… (\(budgetTokensLabel))", isSelected: isReasoningEnabled, action: onOpenThinkingBudgetEditor
                )

            case .none:
                EmptyView()
            }
        } else {
            Text("Not supported")
                .foregroundStyle(.secondary)
        }
    }

    /// Effort rows for the menu. Drops `.none` when the dedicated Off toggle is shown
    /// so its "Off" label is not duplicated (`ReasoningEffort.none.displayName == "Off"`).
    private var menuEffortLevels: [ReasoningEffort] {
        ChatReasoningSupport.effortLevelsForReasoningMenu(
            supported: availableReasoningEffortLevels,
            includesDisableToggle: supportsReasoningDisableToggle
        )
    }

    private func effortLabel(for level: ReasoningEffort) -> String {
        if usesXAIMultiAgentEffortLabels {
            return level.xAIMultiAgentDisplayName
        }
        if level == .xhigh {
            return "Extreme"
        }
        return level.displayName
    }
}
