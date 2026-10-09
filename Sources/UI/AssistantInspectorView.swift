import SwiftUI
import SwiftData

struct AssistantInspectorView: View {
    let assistant: AssistantEntity

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        JinSheet("Assistant Settings") {
            AssistantSettingsEditorView(
                assistant: assistant
            )
        } actions: {
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .onExitCommand { dismiss() }
        // Flexible ScrollView content makes AppKit settle the sheet on `minWidth`
        // rather than `idealWidth`, so the two match on purpose.
        .frame(minWidth: 620, idealWidth: 620, minHeight: 520, idealHeight: 700)
    }
}
