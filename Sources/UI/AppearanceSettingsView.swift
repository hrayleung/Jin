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
    @AppStorage(AppPreferenceKeys.appIconVariant) private var appIconVariant: AppIconVariant = .roseQuartz
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
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(AppIconVariant.allCases) { variant in
                            appIconButton(for: variant)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                }
            } header: {
                Text("App Icon")
            }

            Section("Theme") {
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

            Section("Fonts") {
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

            Section("Code Blocks") {
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

            Section("Thinking Blocks") {
                Picker("Display Mode", selection: thinkingDisplayMode) {
                    ForEach(ThinkingBlockDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(thinkingDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Code Execution") {
                Picker("Display Mode", selection: codeExecutionDisplayMode) {
                    ForEach(CodeExecutionDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(codeExecutionDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Codex Tool Activities") {
                Picker("Display Mode", selection: codexToolDisplayMode) {
                    ForEach(CodexToolDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(codexToolDisplayMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Agent Tool Activities") {
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
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
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

    private func appIconButton(for variant: AppIconVariant) -> some View {
        let isSelected = appIconVariant == variant
        return Button {
            appIconVariant = variant
            applyAppIcon(variant)
        } label: {
            VStack(spacing: 8) {
                iconThumbnail(for: variant)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 0.5)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, Color.accentColor)
                                .offset(x: 4, y: 4)
                        }
                    }
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 2)

                Text(variant.label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconThumbnail(for variant: AppIconVariant) -> some View {
        Group {
            if let url = Bundle.module.url(forResource: variant.thumbnailResourceName, withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let nsImage = NSImage(named: variant.icnsName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Text(variant.rawValue).font(.title2).foregroundStyle(.secondary))
            }
        }
    }

    private func applyAppIcon(_ variant: AppIconVariant) {
        AppIconManager.apply(variant)
    }
}

enum AppIconManager {
    static func apply(_ variant: AppIconVariant) {
        if let url = Bundle.main.url(forResource: variant.icnsName, withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
            // Persist at Finder level so the icon survives app restarts
            if let bundlePath = Bundle.main.bundlePath as String? {
                NSWorkspace.shared.setIcon(icon, forFile: bundlePath)
            }
        }
    }
}
