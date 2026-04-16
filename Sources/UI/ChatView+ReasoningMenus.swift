import SwiftUI
import SwiftData

// MARK: - Reasoning Menus

extension ChatView {

    var reasoningLabel: String {
        guard supportsReasoningControl else { return "Not supported" }
        guard isReasoningEnabled else { return "Off" }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return "Not supported" }

        switch reasoningType {
        case .budget:
            guard let budgetTokens = controls.reasoning?.budgetTokens else { return "On" }
            return "\(budgetTokens) tokens"
        case .effort:
            if providerType == .anthropic || providerType == .claudeManagedAgents {
                if anthropicUsesEffortMode {
                    let effort = controls.reasoning?.effort ?? selectedReasoningConfig?.defaultEffort ?? .high
                    return effort.anthropicDisplayName
                }
                let budgetTokens = controls.reasoning?.budgetTokens ?? anthropicDefaultBudgetTokens
                return "\(budgetTokens) tokens"
            }
            return controls.reasoning?.effort?.displayName ?? "On"
        case .toggle:
            return "On"
        case .none:
            return "Not supported"
        }
    }

    var supportsReasoningSummaryControl: Bool {
        providerType == .openai || providerType == .openaiWebSocket || providerType == .codexAppServer
    }

    @ViewBuilder
    var reasoningMenuContent: some View {
        ReasoningControlMenuView(
            reasoningConfig: selectedReasoningConfig,
            supportsReasoningDisableToggle: supportsReasoningDisableToggle,
            isReasoningEnabled: isReasoningEnabled,
            isAnthropicProvider: providerType == .anthropic || providerType == .claudeManagedAgents,
            supportsCerebrasPreservedThinkingToggle: supportsCerebrasPreservedThinkingToggle,
            cerebrasPreserveThinkingBinding: cerebrasPreserveThinkingBinding,
            availableReasoningEffortLevels: availableReasoningEffortLevels,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl,
            currentReasoningSummary: controls.reasoning?.summary ?? .auto,
            currentReasoningEffort: controls.reasoning?.effort,
            supportsFireworksReasoningHistoryToggle: supportsFireworksReasoningHistoryToggle,
            fireworksReasoningHistoryOptions: fireworksReasoningHistoryOptions,
            fireworksReasoningHistory: fireworksReasoningHistory,
            budgetTokensLabel: String(controls.reasoning?.budgetTokens ?? selectedReasoningConfig?.defaultBudget ?? 1024),
            fireworksReasoningHistoryLabel: { option in
                fireworksReasoningHistoryLabel(for: option)
            },
            menuItemLabel: { title, isSelected in
                menuItemLabel(title, isSelected: isSelected)
            },
            onSetReasoningOff: {
                setReasoningOff()
            },
            onSetReasoningOn: {
                setReasoningOn()
            },
            onOpenThinkingBudgetEditor: {
                openThinkingBudgetEditor()
            },
            onSetReasoningEffort: { effort in
                setReasoningEffort(effort)
            },
            onSetReasoningSummary: { summary in
                setReasoningSummary(summary)
            },
            onSetFireworksReasoningHistory: { value in
                setFireworksReasoningHistory(value)
            }
        )
    }

    var supportsFireworksReasoningHistoryToggle: Bool {
        !fireworksReasoningHistoryOptions.isEmpty
    }

    var fireworksReasoningHistoryOptions: [String] {
        guard providerType == .fireworks else { return [] }
        if isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return ["interleaved", "disabled"]
        }
        if isFireworksModelID(conversationEntity.modelID, canonicalID: "kimi-k2p5")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-4p7")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-5") {
            return ["preserved", "interleaved", "disabled"]
        }
        return []
    }

    var fireworksReasoningHistory: String? {
        controls.providerSpecific["reasoning_history"]?.value as? String
    }

    func setFireworksReasoningHistory(_ value: String?) {
        if let value {
            controls.providerSpecific["reasoning_history"] = AnyCodable(value)
        } else {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
        persistControlsToConversation()
    }

    func isFireworksModelID(_ modelID: String, canonicalID: String) -> Bool {
        fireworksCanonicalModelID(modelID) == canonicalID
    }

    func fireworksReasoningHistoryLabel(for option: String) -> String {
        switch option {
        case "preserved":
            return "Preserved"
        case "interleaved":
            return "Interleaved"
        case "disabled":
            return "Disabled"
        default:
            return option
        }
    }

    var supportsCerebrasPreservedThinkingToggle: Bool {
        guard providerType == .cerebras else { return false }
        return conversationEntity.modelID.lowercased() == "zai-glm-4.7"
    }

    var cerebrasPreserveThinkingBinding: Binding<Bool> {
        Binding(
            get: {
                // Cerebras `clear_thinking` defaults to true. Preserve thinking == clear_thinking false.
                let clear = (controls.providerSpecific["clear_thinking"]?.value as? Bool) ?? true
                return clear == false
            },
            set: { preserve in
                if preserve {
                    controls.providerSpecific["clear_thinking"] = AnyCodable(false)
                } else {
                    // Use provider default (clear_thinking true).
                    controls.providerSpecific.removeValue(forKey: "clear_thinking")
                }
                persistControlsToConversation()
            }
        )
    }

    func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .fixedSize()
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    @ViewBuilder
    func effortLevelButtons(for levels: [ReasoningEffort]) -> some View {
        ForEach(levels, id: \.self) { level in
            Button { setReasoningEffort(level) } label: {
                menuItemLabel(
                    level == .xhigh ? "Extreme" : level.displayName,
                    isSelected: isReasoningEnabled && controls.reasoning?.effort == level
                )
            }
        }
    }
}
