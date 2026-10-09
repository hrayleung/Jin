import SwiftUI

struct ShortcutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shortcutHintController: ShortcutHintController
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore

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
        JinSheet(action.title) {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                ShortcutRecorderCard(binding: $draftBinding, validationMessage: $validationMessage)
                HStack(spacing: JinSpacing.large) {
                    ShortcutEditorCurrentDefaultLabel(title: "Current", value: currentBinding?.displayLabel ?? "None")
                    ShortcutEditorCurrentDefaultLabel(title: "Default", value: defaultBinding?.displayLabel ?? "None")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        } actions: {
            Menu("More") {
                Button("Disable Shortcut") {
                    draftBinding = nil
                    validationMessage = nil
                }
                Button("Restore Default") {
                    draftBinding = defaultBinding
                    validationMessage = nil
                }
            }
            .fixedSize()
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                if draftBinding == defaultBinding { onRestoreDefault() } else { onSave(draftBinding) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .frame(width: 480, height: 300)
        .onAppear {
            shortcutHintController.isCaptureActive = true
            validateDraftBinding()
        }
        .onDisappear {
            shortcutHintController.isCaptureActive = false
        }
        .onChange(of: draftBinding) { _, _ in
            validateDraftBinding()
        }
    }

    private var canSave: Bool {
        draftBinding != currentBinding && validationMessage == nil
    }

    private func validateDraftBinding() {
        validationMessage = shortcutsStore.fixedShortcutConflictMessage(for: draftBinding)
    }
}
