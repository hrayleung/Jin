import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeBlockShowLineNumbers) private var codeBlockShowLineNumbers = false
    @AppStorage(AppPreferenceKeys.thinkingBlockDisplayMode) private var thinkingDisplayModeRaw = ThinkingBlockDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.codeExecutionDisplayMode) private var codeExecutionDisplayModeRaw = CodeExecutionDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.useOverlayScrollbars) private var useOverlayScrollbars = true
    @AppStorage(AppPreferenceKeys.showConversationMinimap) private var showConversationMinimap = true

    @State private var showingAppFontPicker = false
    @State private var showingCodeFontPicker = false

    private var thinkingDisplayMode: Binding<ThinkingBlockDisplayMode> {
        Binding(
            get: { ThinkingBlockDisplayMode(rawValue: thinkingDisplayModeRaw) ?? .expanded },
            set: { thinkingDisplayModeRaw = $0.rawValue }
        )
    }

    private var codeExecutionDisplayMode: Binding<CodeExecutionDisplayMode> {
        Binding(
            get: { CodeExecutionDisplayMode(rawValue: codeExecutionDisplayModeRaw) ?? .expanded },
            set: { codeExecutionDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        JinSettingsPage(title: "Appearance") {
            JinSettingsSection("Theme") {
                AppearanceModePicker(selection: $appAppearanceMode)
                    .padding(.vertical, 6)
            }

            JinSettingsSection("Typography") {
                JinSettingsControlRow("App Font") {
                    fontPickerButton(title: appFontDisplayName) { showingAppFontPicker = true }
                }
                JinSettingsControlRow("Code Font") {
                    fontPickerButton(title: codeFontDisplayName) { showingCodeFontPicker = true }
                }
            }

            JinSettingsSection("Conversation") {
                JinSettingsToggleRow("Overlay Scrollbars", isOn: $useOverlayScrollbars)
                JinSettingsToggleRow(
                    "Conversation Minimap",
                    supportingText: "Preview and jump between turns from the edge of the chat.",
                    isOn: $showConversationMinimap
                )
                JinSettingsToggleRow("Code Line Numbers", isOn: $codeBlockShowLineNumbers)
                JinSettingsPickerRow("Thinking", selection: thinkingDisplayMode) {
                    ForEach(ThinkingBlockDisplayMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                JinSettingsPickerRow("Code Execution", selection: codeExecutionDisplayMode) {
                    ForEach(CodeExecutionDisplayMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
            }

        }
        .sheet(isPresented: $showingAppFontPicker) {
            FontPickerSheet(
                title: "App Font",
                subtitle: "Pick the default typeface used across the app.",
                selectedFontFamily: $appFontFamily
            )
        }
        .sheet(isPresented: $showingCodeFontPicker) {
            FontPickerSheet(
                title: "Code Font",
                subtitle: "Used for markdown code blocks across chat and artifact previews.",
                selectedFontFamily: $codeFontFamily
            )
        }
        .onAppear {
            normalizeTypographyPreferences()
        }
    }

    private func fontPickerButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: JinSpacing.small) {
                Text(title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.borderless)
    }

    private var appFontDisplayName: String {
        JinTypography.displayName(for: appFontFamily)
    }

    private var codeFontDisplayName: String {
        JinTypography.displayName(for: codeFontFamily)
    }

    private func normalizeTypographyPreferences() {
        appFontFamily = JinTypography.normalizedFontPreference(appFontFamily)
        codeFontFamily = JinTypography.normalizedFontPreference(codeFontFamily)
    }
}

enum AppIconManager {
    static let bundleIconName = "AppIcon"

    static func applyDefaultIcon() {
        if let url = Bundle.main.url(forResource: bundleIconName, withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
            if let bundlePath = Bundle.main.bundlePath as String? {
                NSWorkspace.shared.setIcon(icon, forFile: bundlePath)
            }
        }
    }
}
