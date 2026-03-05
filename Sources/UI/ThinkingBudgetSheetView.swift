import SwiftUI

struct ThinkingBudgetSheetView: View {
    let usesAdaptiveThinking: Bool
    let usesEffortMode: Bool
    let modelID: String
    let modelMaxOutputTokens: Int?
    let supportsMaxEffort: Bool

    @Binding var thinkingBudgetDraft: String
    @Binding var maxTokensDraft: String
    @Binding var effortSelection: ReasoningEffort

    var isValid: Bool
    var validationWarning: String?

    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: JinSpacing.medium + 2) {
                    modeBanner

                    if usesEffortMode {
                        settingRow("Effort") {
                            Picker("Effort", selection: $effortSelection) {
                                Text("Low").tag(ReasoningEffort.low)
                                Text("Medium").tag(ReasoningEffort.medium)
                                Text("High").tag(ReasoningEffort.high)
                                if supportsMaxEffort {
                                    Text("Max").tag(ReasoningEffort.xhigh)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }
                    }

                    if !usesAdaptiveThinking {
                        settingRow("Thinking budget") {
                            tokenField(text: $thinkingBudgetDraft)
                        }
                    }

                    settingRow("Max output tokens") {
                        VStack(alignment: .trailing, spacing: 2) {
                            tokenField(text: $maxTokensDraft)
                            if let modelMaxOutputTokens {
                                Text("Limit: \(modelMaxOutputTokens.formatted())")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if let validationWarning {
                        HStack(spacing: JinSpacing.xSmall) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption2)
                            Text(validationWarning)
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }
                }
                .padding(JinSpacing.large)
                .jinSurface(.raised, cornerRadius: JinRadius.large)

                Spacer(minLength: JinSpacing.medium)
            }
            .padding(JinSpacing.large)
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Thinking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(width: 480)
    }

    // MARK: - Components

    private var modeBanner: some View {
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

    @ViewBuilder
    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Text(title)
                .font(.body)
            Spacer(minLength: 0)
            control()
        }
    }

    @ViewBuilder
    private func tokenField(text: Binding<String>) -> some View {
        TextField("", text: text)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
    }
}
