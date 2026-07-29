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
        JinSettingsPage {
            JinSettingsSection("Theme") {
                JinSettingsPickerRow("Mode", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                JinSettingsToggleRow(
                    "Overlay Scrollbars",
                    supportingText: "Fade in during scroll, hide when idle.",
                    isOn: $useOverlayScrollbars
                )
            }

            JinSettingsSection("Fonts") {
                JinSettingsControlRow("App Font") {
                    Button(appFontDisplayName) {
                        showingAppFontPicker = true
                    }
                    .buttonStyle(.borderless)
                }

                JinSettingsControlRow("Code Font") {
                    Button(codeFontDisplayName) {
                        showingCodeFontPicker = true
                    }
                    .buttonStyle(.borderless)
                }
            }

            JinSettingsSection("Chat") {
                JinSettingsToggleRow(
                    "Conversation Minimap",
                    supportingText: "A rail of turn markers along the left edge of the chat. Hover to preview, click to jump.",
                    isOn: $showConversationMinimap
                )
            }

            JinSettingsSection("Code Blocks") {
                JinSettingsToggleRow("Show Line Numbers", isOn: $codeBlockShowLineNumbers)
            }

            JinSettingsSection("Thinking Blocks") {
                JinSettingsPickerRow(
                    "Display Mode",
                    supportingText: thinkingDisplayMode.wrappedValue.description,
                    selection: thinkingDisplayMode
                ) {
                    ForEach(ThinkingBlockDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            JinSettingsSection("Code Execution") {
                JinSettingsPickerRow(
                    "Display Mode",
                    supportingText: codeExecutionDisplayMode.wrappedValue.description,
                    selection: codeExecutionDisplayMode
                ) {
                    ForEach(CodeExecutionDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
        }
        .navigationTitle("Appearance")
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
