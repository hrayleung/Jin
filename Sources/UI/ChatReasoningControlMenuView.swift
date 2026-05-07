import SwiftUI

struct ReasoningControlMenuView<MenuItemLabel: View>: View {
    let reasoningConfig: ModelReasoningConfig?
    let supportsReasoningDisableToggle: Bool
    let isReasoningEnabled: Bool
    let isAnthropicProvider: Bool
    let supportsCerebrasPreservedThinkingToggle: Bool
    let cerebrasPreserveThinkingBinding: Binding<Bool>
    let availableReasoningEffortLevels: [ReasoningEffort]
    let supportsReasoningSummaryControl: Bool
    let currentReasoningSummary: ReasoningSummary
    let currentReasoningEffort: ReasoningEffort?
    let supportsFireworksReasoningHistoryToggle: Bool
    let fireworksReasoningHistoryOptions: [String]
    let fireworksReasoningHistory: String?
    let budgetTokensLabel: String
    let fireworksReasoningHistoryLabel: (String) -> String
    let menuItemLabel: (String, Bool) -> MenuItemLabel
    let onSetReasoningOff: () -> Void
    let onSetReasoningOn: () -> Void
    let onOpenThinkingBudgetEditor: () -> Void
    let onSetReasoningEffort: (ReasoningEffort) -> Void
    let onSetReasoningSummary: (ReasoningSummary) -> Void
    let onSetFireworksReasoningHistory: (String?) -> Void

    @ViewBuilder
    var body: some View {
        if let reasoningConfig, reasoningConfig.type != .none {
            if supportsReasoningDisableToggle {
                Button(action: onSetReasoningOff) {
                    menuItemLabel("Off", !isReasoningEnabled)
                }
            }

            switch reasoningConfig.type {
            case .toggle:
                Button(action: onSetReasoningOn) {
                    menuItemLabel("On", isReasoningEnabled)
                }

                if supportsCerebrasPreservedThinkingToggle {
                    Divider()
                    Toggle("Preserve thinking", isOn: cerebrasPreserveThinkingBinding)
                        .help("Keeps GLM thinking across turns (maps to clear_thinking: false).")
                }

            case .effort:
                if isAnthropicProvider {
                    Button(action: onOpenThinkingBudgetEditor) {
                        menuItemLabel("Configure thinking…", isReasoningEnabled)
                    }
                } else {
                    ForEach(availableReasoningEffortLevels, id: \.self) { level in
                        Button {
                            onSetReasoningEffort(level)
                        } label: {
                            menuItemLabel(
                                level == .xhigh ? "Extreme" : level.displayName,
                                isReasoningEnabled && currentReasoningEffort == level
                            )
                        }
                    }
                }

                if !isAnthropicProvider && supportsReasoningSummaryControl {
                    Divider()
                    Text("Reasoning summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(ReasoningSummary.allCases, id: \.self) { summary in
                        Button {
                            onSetReasoningSummary(summary)
                        } label: {
                            menuItemLabel(summary.displayName, currentReasoningSummary == summary)
                        }
                    }
                }

                if supportsFireworksReasoningHistoryToggle {
                    Divider()
                    Text("Thinking history")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        onSetFireworksReasoningHistory(nil)
                    } label: {
                        menuItemLabel("Default (model)", fireworksReasoningHistory == nil)
                    }

                    ForEach(fireworksReasoningHistoryOptions, id: \.self) { option in
                        Button {
                            onSetFireworksReasoningHistory(option)
                        } label: {
                            menuItemLabel(
                                fireworksReasoningHistoryLabel(option),
                                fireworksReasoningHistory == option
                            )
                        }
                    }
                }

            case .budget:
                Button(action: onOpenThinkingBudgetEditor) {
                    menuItemLabel("Budget tokens… (\(budgetTokensLabel))", isReasoningEnabled)
                }

            case .none:
                EmptyView()
            }
        } else {
            Text("Not supported")
                .foregroundStyle(.secondary)
        }
    }
}
