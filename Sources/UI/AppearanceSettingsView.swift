import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeBlockDisplayMode) private var codeBlockDisplayModeRaw = CodeBlockDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.codeBlockShowLineNumbers) private var codeBlockShowLineNumbers = false
    @AppStorage(AppPreferenceKeys.codeBlockCollapseLineThreshold) private var codeBlockCollapseLineThreshold = 25
    @AppStorage(AppPreferenceKeys.thinkingBlockDisplayMode) private var thinkingDisplayModeRaw = ThinkingBlockDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.codexToolDisplayMode) private var codexToolDisplayModeRaw = CodexToolDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.codeExecutionDisplayMode) private var codeExecutionDisplayModeRaw = CodeExecutionDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.agentToolDisplayMode) private var agentToolDisplayModeRaw = AgentToolDisplayMode.expanded.rawValue
    @AppStorage(AppPreferenceKeys.useOverlayScrollbars) private var useOverlayScrollbars = true

    @State private var showingAppFontPicker = false
    @State private var showingCodeFontPicker = false

    private var codeBlockDisplayMode: Binding<CodeBlockDisplayMode> {
        Binding(
            get: { CodeBlockDisplayMode(rawValue: codeBlockDisplayModeRaw) ?? .expanded },
            set: { codeBlockDisplayModeRaw = $0.rawValue }
        )
    }

    private var thinkingDisplayMode: Binding<ThinkingBlockDisplayMode> {
        Binding(
            get: { ThinkingBlockDisplayMode(rawValue: thinkingDisplayModeRaw) ?? .expanded },
            set: { thinkingDisplayModeRaw = $0.rawValue }
        )
    }

    private var codexToolDisplayMode: Binding<CodexToolDisplayMode> {
        Binding(
            get: { CodexToolDisplayMode(rawValue: codexToolDisplayModeRaw) ?? .expanded },
            set: { codexToolDisplayModeRaw = $0.rawValue }
        )
    }

    private var codeExecutionDisplayMode: Binding<CodeExecutionDisplayMode> {
        Binding(
            get: { CodeExecutionDisplayMode(rawValue: codeExecutionDisplayModeRaw) ?? .expanded },
            set: { codeExecutionDisplayModeRaw = $0.rawValue }
        )
    }

    private var agentToolDisplayMode: Binding<AgentToolDisplayMode> {
        Binding(
            get: { AgentToolDisplayMode(rawValue: agentToolDisplayModeRaw) ?? .expanded },
            set: { agentToolDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        JinSettingsPage {
            JinSettingsSection("Theme") {
                Picker("Mode", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Toggle("Overlay Scrollbars", isOn: $useOverlayScrollbars)

                Text("When enabled, scrollbars fade in during scrolling and hide when idle. Turn off to follow the system preference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JinSettingsSection("Fonts") {
                LabeledContent("App Font") {
                    Button(appFontDisplayName) {
                        showingAppFontPicker = true
                    }
                    .buttonStyle(.borderless)
                }

                LabeledContent("Code Font") {
                    Button(codeFontDisplayName) {
                        showingCodeFontPicker = true
                    }
                    .buttonStyle(.borderless)
                }
            }

            JinSettingsSection("Code Blocks") {
                Picker("Long Blocks", selection: codeBlockDisplayMode) {
                    ForEach(CodeBlockDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Toggle("Show Line Numbers", isOn: $codeBlockShowLineNumbers)

                HStack {
                    Text("Collapse After")
                    TextField(
                        "",
                        value: $codeBlockCollapseLineThreshold,
                        format: .number
                    )
                    .frame(width: 52)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        codeBlockCollapseLineThreshold = max(1, codeBlockCollapseLineThreshold)
                    }
                    Text("Lines")
                }
                .disabled(codeBlockDisplayMode.wrappedValue == .expanded)

                Text(codeBlockDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JinSettingsSection("Thinking Blocks") {
                Picker("Display Mode", selection: thinkingDisplayMode) {
                    ForEach(ThinkingBlockDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(thinkingDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JinSettingsSection("Code Execution") {
                Picker("Display Mode", selection: codeExecutionDisplayMode) {
                    ForEach(CodeExecutionDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(codeExecutionDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JinSettingsSection("Codex Tool Activities") {
                Picker("Display Mode", selection: codexToolDisplayMode) {
                    ForEach(CodexToolDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(codexToolDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JinSettingsSection("Agent Tool Activities") {
                Picker("Display Mode", selection: agentToolDisplayMode) {
                    ForEach(AgentToolDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(agentToolDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
