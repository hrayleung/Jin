import SwiftUI

struct ThinkingBudgetSheetView: View {
    let usesEffortMode: Bool
    let summaryText: String
    let footnoteText: String
    let budgetPlaceholder: String
    let maxTokensPlaceholder: String
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
            Form {
                Section("Claude thinking") {
                    VStack(alignment: .leading, spacing: JinSpacing.medium) {
                        Text(summaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        if usesEffortMode {
                            effortRow
                        } else {
                            budgetTokensRow
                        }

                        maxOutputTokensRow

                        if let modelMaxOutputTokens {
                            Text("Model max output tokens: \(modelMaxOutputTokens.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let validationWarning {
                            warningBanner(validationWarning)
                        }

                        Label(footnoteText, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(JinSpacing.large)
                    .jinSurface(.raised, cornerRadius: JinRadius.large)
                    .listRowInsets(
                        EdgeInsets(
                            top: JinSpacing.small,
                            leading: JinSpacing.small,
                            bottom: JinSpacing.small,
                            trailing: JinSpacing.small
                        )
                    )
                    .listRowBackground(Color.clear)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
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
        .frame(minWidth: 640, idealWidth: 700)
    }

    // MARK: - Rows

    private var effortRow: some View {
        controlRow("Thinking effort") {
            Picker("Thinking effort", selection: $effortSelection) {
                Text("Low").tag(ReasoningEffort.low)
                Text("Medium").tag(ReasoningEffort.medium)
                Text("High").tag(ReasoningEffort.high)
                if supportsMaxEffort {
                    Text("Max").tag(ReasoningEffort.xhigh)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180, alignment: .trailing)
        }
    }

    private var budgetTokensRow: some View {
        controlRow("Thinking budget") {
            tokenField(placeholder: budgetPlaceholder, text: $thinkingBudgetDraft)
        }
    }

    private var maxOutputTokensRow: some View {
        controlRow("Max output tokens") {
            tokenField(placeholder: maxTokensPlaceholder, text: $maxTokensDraft)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func controlRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            control()
        }
    }

    @ViewBuilder
    private func tokenField(placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder))
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 170)
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .padding(JinSpacing.small)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
    }
}
