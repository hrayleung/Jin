import SwiftUI

struct ShortcutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let action: AppShortcutAction
    let currentBinding: AppShortcutBinding?
    let defaultBinding: AppShortcutBinding?
    let onSave: (AppShortcutBinding?) -> Void
    let onRestoreDefault: () -> Void

    @State private var draftBinding: AppShortcutBinding?
    @State private var validationMessage: String?

    init(
        action: AppShortcutAction,
        currentBinding: AppShortcutBinding?,
        defaultBinding: AppShortcutBinding?,
        onSave: @escaping (AppShortcutBinding?) -> Void,
        onRestoreDefault: @escaping () -> Void
    ) {
        self.action = action
        self.currentBinding = currentBinding
        self.defaultBinding = defaultBinding
        self.onSave = onSave
        self.onRestoreDefault = onRestoreDefault
        _draftBinding = State(initialValue: currentBinding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text(action.title)
                .font(.headline)

            ShortcutRecorderCard(
                binding: $draftBinding,
                validationMessage: $validationMessage
            )

            HStack(spacing: JinSpacing.large) {
                ShortcutEditorCurrentDefaultLabel(
                    title: "Current",
                    value: currentBinding?.displayLabel ?? "None"
                )
                ShortcutEditorCurrentDefaultLabel(
                    title: "Default",
                    value: defaultBinding?.displayLabel ?? "None"
                )
            }

            Spacer(minLength: 0)

            HStack(spacing: JinSpacing.small) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button("Disable") {
                    draftBinding = nil
                    validationMessage = nil
                }

                Button("Restore Default") {
                    draftBinding = defaultBinding
                    validationMessage = nil
                }

                Button("Save") {
                    if draftBinding == defaultBinding {
                        onRestoreDefault()
                    } else {
                        onSave(draftBinding)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460, height: 250)
    }

    private var canSave: Bool {
        draftBinding != currentBinding
    }
}
