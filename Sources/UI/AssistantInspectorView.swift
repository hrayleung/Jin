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
        .frame(minWidth: 600, idealWidth: 700, minHeight: 600, idealHeight: 700)
    }
}
