import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore
    @State private var editingAction: AppShortcutAction?

    var body: some View {
        JinSettingsPage {
            ForEach(AppShortcutSection.allCases, id: \.rawValue) { section in
                JinSettingsSection(section.title) {
                    ForEach(actions(in: section)) { action in
                        shortcutRow(for: action)
                    }
                }
            }

            JinSettingsSection("Actions") {
                Button("Restore All Defaults") {
                    shortcutsStore.resetAllToDefaults()
                }
                .disabled(!hasCustomizations)
            }
        }
        .navigationTitle("Keyboard Shortcuts")
        .sheet(item: $editingAction) { action in
            ShortcutEditorSheet(
                action: action,
                currentBinding: shortcutsStore.binding(for: action),
                defaultBinding: action.defaultBinding,
                onSave: { binding in
                    _ = shortcutsStore.setBinding(binding, for: action)
                },
                onRestoreDefault: {
                    shortcutsStore.restoreDefault(for: action)
                }
            )
        }
    }

    private var hasCustomizations: Bool {
        AppShortcutAction.allCases.contains { shortcutsStore.isCustomized($0) }
    }

    private func shortcutRow(for action: AppShortcutAction) -> some View {
        KeyboardShortcutSettingsRow(
            title: action.title,
            displayLabel: shortcutsStore.displayLabel(for: action),
            isCustomized: shortcutsStore.isCustomized(action)
        ) {
            editingAction = action
        }
    }

    private func actions(in section: AppShortcutSection) -> [AppShortcutAction] {
        AppShortcutAction.allCases.filter { $0.section == section }
    }
}
