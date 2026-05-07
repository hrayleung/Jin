import SwiftUI

struct ThinkingBudgetEditorCard: View {
    let usesAdaptiveThinking: Bool
    let usesEffortMode: Bool
    let modelMaxOutputTokens: Int?
    let supportedEffortLevels: [ReasoningEffort]
    let supportsThinkingDisplayControl: Bool
    let validationWarning: String?

    @Binding var thinkingBudgetDraft: String
    @Binding var maxTokensDraft: String
    @Binding var thinkingDisplaySelection: AnthropicThinkingDisplay
    @Binding var effortSelection: ReasoningEffort

    var body: some View {
        JinSettingsCard(spacing: JinSpacing.medium + 2) {
            modeBanner
            effortRow
            thinkingDisplayRow
            thinkingBudgetRow
            maxOutputTokensRow
            validationWarningRow
        }
    }

    private var modeBanner: some View {
        ThinkingBudgetModeBanner(usesAdaptiveThinking: usesAdaptiveThinking)
    }

    @ViewBuilder
    private var effortRow: some View {
        if usesEffortMode {
            ThinkingBudgetSettingRow("Effort") {
                effortPicker
            }
        }
    }

    @ViewBuilder
    private var thinkingDisplayRow: some View {
        if supportsThinkingDisplayControl {
            ThinkingBudgetSettingRow("Visible thinking") {
                thinkingDisplayPicker
            }
        }
    }

    private var thinkingDisplayPicker: some View {
        Picker("Visible thinking", selection: $thinkingDisplaySelection) {
            ForEach(AnthropicThinkingDisplay.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 220)
    }

    @ViewBuilder
    private var thinkingBudgetRow: some View {
        if !usesAdaptiveThinking {
            ThinkingBudgetSettingRow("Thinking budget") {
                ThinkingBudgetTokenField(text: $thinkingBudgetDraft)
            }
        }
    }

    private var maxOutputTokensRow: some View {
        ThinkingBudgetSettingRow("Max output tokens") {
            maxOutputTokensControl
        }
    }

    private var maxOutputTokensControl: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ThinkingBudgetTokenField(text: $maxTokensDraft)
            maxOutputTokensLimitLabel
        }
    }

    @ViewBuilder
    private var maxOutputTokensLimitLabel: some View {
        if let modelMaxOutputTokens {
            Text("Limit: \(modelMaxOutputTokens.formatted())")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var validationWarningRow: some View {
        if let validationWarning {
            ThinkingBudgetValidationWarning(message: validationWarning)
        }
    }

    @ViewBuilder
    private var effortPicker: some View {
        if supportedEffortLevels.count <= 4 {
            Picker("Effort", selection: $effortSelection) {
                ForEach(supportedEffortLevels, id: \.self) { level in
                    Text(level.anthropicDisplayName).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 320)
        } else {
            Picker("Effort", selection: $effortSelection) {
                ForEach(supportedEffortLevels, id: \.self) { level in
                    Text(level.anthropicDisplayName).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 140)
        }
    }
}

private struct ThinkingBudgetModeBanner: View {
    let usesAdaptiveThinking: Bool

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: usesAdaptiveThinking ? "brain" : "gauge.with.dots.needle.33percent")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(usesAdaptiveThinking
                 ? "Adaptive thinking — Claude decides how deeply to think."
                 : "Budget thinking — set a token limit for reasoning.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.bottom, JinSpacing.xSmall)
    }
}

private struct ThinkingBudgetSettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    init(
        _ title: String,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Text(title)
                .font(.body)
            Spacer(minLength: 0)
            control()
        }
    }
}

private struct ThinkingBudgetTokenField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
    }
}

private struct ThinkingBudgetValidationWarning: View {
    let message: String

    var body: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption2)
            Text(message)
                .foregroundStyle(.orange)
        }
        .font(.caption)
    }
}
