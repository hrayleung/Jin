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
            let effort = controls.reasoning?.effort ?? selectedReasoningConfig?.defaultEffort
            if let effort, usesXAIMultiAgentEffortLabels {
                return effort.xAIMultiAgentDisplayName
            }
            let base = effort?.displayName ?? "On"
            if controls.reasoning?.mode == .pro {
                return "\(base) · Pro"
            }
            return base
        case .toggle:
            return "On"
        case .none:
            return "Not supported"
        }
    }

    var supportsReasoningSummaryControl: Bool {
        providerType == .openai || providerType == .openaiWebSocket
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
            usesXAIMultiAgentEffortLabels: usesXAIMultiAgentEffortLabels,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl,
            currentReasoningSummary: controls.reasoning?.summary ?? .auto,
            currentReasoningEffort: controls.reasoning?.effort,
            supportsProMode: supportsOpenAIProMode,
            isProModeEnabled: controls.reasoning?.mode == .pro,
            supportsReasoningContext: supportsOpenAIReasoningContext,
            currentReasoningContext: controls.reasoning?.context,
            supportsTextVerbosity: supportsOpenAITextVerbosity,
            currentTextVerbosity: controls.textVerbosity,
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
            onSetProMode: { enabled in
                setOpenAIProMode(enabled)
            },
            onSetReasoningContext: { mode in
                setOpenAIReasoningContext(mode)
            },
            onSetTextVerbosity: { verbosity in
                setTextVerbosity(verbosity)
            },
            onSetFireworksReasoningHistory: { value in
                setFireworksReasoningHistory(value)
            }
        )
    }

    var supportsOpenAIProMode: Bool {
        ModelCapabilityRegistry.supportsOpenAIStyleProMode(
            for: providerType,
            modelID: activeModelID
        )
    }

    var supportsOpenAIReasoningContext: Bool {
        ModelCapabilityRegistry.supportsOpenAIStyleReasoningContext(
            for: providerType,
            modelID: activeModelID
        )
    }

    var supportsOpenAITextVerbosity: Bool {
        ModelCapabilityRegistry.supportsOpenAIStyleVerbosity(
            for: providerType,
            modelID: activeModelID
        )
    }

    func setOpenAIProMode(_ enabled: Bool) {
        var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
        reasoning.mode = enabled ? .pro : .standard
        if enabled {
            // Adapter only emits `reasoning` when enabled && effort != none.
            // Seed a default effort so Pro mode alone still produces reasoning.mode=pro.
            ChatReasoningSupport.ensureOpenAIReasoningActive(
                &reasoning,
                defaultEffort: selectedReasoningConfig?.defaultEffort ?? .medium,
                supportsReasoningSummaryControl: supportsReasoningSummaryControl
            )
        }
        controls.reasoning = reasoning
        persistControlsToConversation()
    }

    func setOpenAIReasoningContext(_ mode: ReasoningContextMode?) {
        var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
        reasoning.context = mode
        if mode != nil {
            ChatReasoningSupport.ensureOpenAIReasoningActive(
                &reasoning,
                defaultEffort: selectedReasoningConfig?.defaultEffort ?? .medium,
                supportsReasoningSummaryControl: supportsReasoningSummaryControl
            )
        }
        controls.reasoning = reasoning
        persistControlsToConversation()
    }

    func setTextVerbosity(_ verbosity: TextVerbosity?) {
        controls.textVerbosity = verbosity
        persistControlsToConversation()
    }

    var supportsFireworksReasoningHistoryToggle: Bool {
        !fireworksReasoningHistoryOptions.isEmpty
    }

    var fireworksReasoningHistoryOptions: [String] {
        guard providerType == .fireworks else { return [] }
        if isFireworksMiniMaxM2FamilyModel(activeModelID) {
            return ["interleaved", "disabled"]
        }
        if isFireworksModelID(activeModelID, canonicalID: "kimi-k2p5")
            || isFireworksModelID(activeModelID, canonicalID: "glm-4p7")
            || isFireworksModelID(activeModelID, canonicalID: "glm-5") {
            return ["preserved", "interleaved", "disabled"]
        }
        return []
    }

    var fireworksReasoningHistory: String? {
        ChatReasoningSupport.fireworksReasoningHistory(controls: controls)
    }

    func setFireworksReasoningHistory(_ value: String?) {
        controls = ChatReasoningSupport.setFireworksReasoningHistory(value, controls: controls)
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
        return activeModelID.lowercased() == "zai-glm-4.7"
    }

    var cerebrasPreserveThinkingBinding: Binding<Bool> {
        Binding(
            get: {
                ChatReasoningSupport.cerebrasPreservesThinking(controls: controls)
            },
            set: { preserve in
                controls = ChatReasoningSupport.setCerebrasPreservesThinking(preserve, controls: controls)
                persistControlsToConversation()
            }
        )
    }

    func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        // Leading checkmark is the reliable macOS menu selection affordance;
        // trailing Spacer checkmarks collapse / vanish in nested Menu flyouts.
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 14, alignment: .center)
            Text(title)
                .fixedSize()
        }
    }

    var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: activeModelID,
            // A band the provider reported at fetch time beats the bundled catalog:
            // it is the only thing that is right for a model newer than this build.
            declaredEfforts: resolvedModelSettings?.reasoningConfig?.supportedEfforts
        )
    }

    var usesXAIMultiAgentEffortLabels: Bool {
        ModelCapabilityRegistry.usesXAIMultiAgentEffortLabels(
            for: providerType,
            modelID: activeModelID
        )
    }
}
