import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue

    @State private var showingAppFontPicker = false
    @State private var showingCodeFontPicker = false

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Mode", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
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
                subtitle: "Used for markdown code blocks in chat.",
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
