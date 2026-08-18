import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore
    @EnvironmentObject private var shortcutHintController: ShortcutHintController
    @AppStorage(AppPreferenceKeys.showShortcutHints) private var showShortcutHints = true
    @State private var editingAction: AppShortcutAction?

    var body: some View {
        JinSettingsPage {
            JinSettingsSection("Discovery") {
                JinSettingsToggleRow(
                    "Hold ⌘ to preview shortcuts",
                    supportingText: "Hold ⌘ briefly to show badges on the matching buttons. Release ⌘ to hide them.",
                    isOn: $showShortcutHints
                )
            }

            ForEach(AppShortcutSection.allCases, id: \.rawValue) { section in
                JinSettingsSection(section.title, detail: section.subtitle) {
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
        .onChange(of: showShortcutHints) { _, enabled in
            shortcutHintController.isEnabled = enabled
        }
        .onAppear {
            shortcutHintController.isEnabled = showShortcutHints
        }
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
