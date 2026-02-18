import SwiftUI
#if os(macOS)
import AppKit
#endif

struct KeyboardShortcutsSettingsView: View {
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore
    @State private var editingAction: AppShortcutAction?

    var body: some View {
        Form {
            ForEach(AppShortcutSection.allCases, id: \.rawValue) { section in
                Section(section.title) {
                    ForEach(actions(in: section)) { action in
                        shortcutRow(for: action)
                    }
                }
            }

            Section {
                Button("Restore All Defaults") {
                    shortcutsStore.resetAllToDefaults()
                }
                .disabled(!hasCustomizations)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
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

    @ViewBuilder
    private func shortcutRow(for action: AppShortcutAction) -> some View {
        Button {
            editingAction = action
        } label: {
            HStack(spacing: JinSpacing.small) {
                Text(action.title)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if shortcutsStore.isCustomized(action) {
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(JinSemanticColor.subtleSurface)
                        )
                }

                Spacer(minLength: JinSpacing.small)

                ShortcutKeyCapsule(label: shortcutsStore.displayLabel(for: action))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit shortcut")
    }

    private func actions(in section: AppShortcutSection) -> [AppShortcutAction] {
        AppShortcutAction.allCases.filter { $0.section == section }
    }
}

private struct ShortcutKeyCapsule: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 56, alignment: .center)
            .background(
                Capsule(style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.5), lineWidth: JinStrokeWidth.hairline)
            )
    }
}

private struct ShortcutEditorSheet: View {
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
                currentDefaultLabel(title: "Current", value: currentBinding?.displayLabel ?? "None")
                currentDefaultLabel(title: "Default", value: defaultBinding?.displayLabel ?? "None")
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

    @ViewBuilder
    private func currentDefaultLabel(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
        .font(.caption)
    }

    private var canSave: Bool {
        draftBinding != currentBinding
    }
}

private struct ShortcutRecorderCard: View {
    @Binding var binding: AppShortcutBinding?
    @Binding var validationMessage: String?
    @State private var isRecorderActive = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .fill(JinSemanticColor.subtleSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
                )

            VStack(spacing: 4) {
                Text(binding?.displayLabel ?? "None")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, JinSpacing.small)

            #if os(macOS)
            ShortcutCaptureView(
                isFirstResponder: $isRecorderActive,
                onCapture: { capturedBinding in
                    binding = capturedBinding
                    validationMessage = nil
                },
                onClear: {
                    binding = nil
                    validationMessage = nil
                },
                onValidationError: { message in
                    validationMessage = message
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
        .frame(height: 88)
        .onTapGesture {
            isRecorderActive = true
        }
    }
}

#if os(macOS)
private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isFirstResponder: Bool
    let onCapture: (AppShortcutBinding) -> Void
    let onClear: () -> Void
    let onValidationError: (String) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onCapture = onCapture
        view.onClear = onClear
        view.onValidationError = onValidationError
        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onClear = onClear
        nsView.onValidationError = onValidationError
        guard isFirstResponder, nsView.window?.firstResponder !== nsView else { return }
        nsView.window?.makeFirstResponder(nsView)
    }

    final class CaptureNSView: NSView {
        var onCapture: ((AppShortcutBinding) -> Void)?
        var onClear: (() -> Void)?
        var onValidationError: ((String) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.type == .keyDown else { return false }
            return handleKeyEvent(event)
        }

        override func keyDown(with event: NSEvent) {
            _ = handleKeyEvent(event)
        }

        @discardableResult
        private func handleKeyEvent(_ event: NSEvent) -> Bool {
            let modifiers = AppShortcutModifiers(eventFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask))

            if modifiers.isEmpty && (event.keyCode == 51 || event.keyCode == 117) {
                onClear?()
                return true
            }

            guard modifiers.includesCommandKey else {
                NSSound.beep()
                onValidationError?("Please include Command (⌘).")
                return true
            }

            guard let key = AppShortcutKey(event: event) else {
                NSSound.beep()
                onValidationError?("This key is not supported.")
                return true
            }

            onCapture?(AppShortcutBinding(key: key, modifiers: modifiers))
            return true
        }
    }
}
#endif
