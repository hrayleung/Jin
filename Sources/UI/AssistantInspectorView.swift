import SwiftUI
import SwiftData

struct AssistantInspectorView: View {
    let assistant: AssistantEntity

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AssistantSettingsEditorView(
                assistant: assistant
            )
            .navigationTitle("Assistant Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        // Flexible ScrollView content makes AppKit settle the sheet on `minWidth`
        // rather than `idealWidth`, so the two match on purpose.
        .frame(minWidth: 620, idealWidth: 620, minHeight: 520, idealHeight: 700)
    }
}
