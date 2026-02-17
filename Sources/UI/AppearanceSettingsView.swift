import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.appIconVariant) private var appIconVariant: AppIconVariant = .a

    @State private var showingAppFontPicker = false
    @State private var showingCodeFontPicker = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    Spacer()
                    ForEach(AppIconVariant.allCases) { variant in
                        appIconButton(for: variant)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            } header: {
                Text("App Icon")
            }

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
            if let url = Bundle.main.url(forResource: variant.thumbnailResourceName, withExtension: "png"),
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
        }
    }
}
