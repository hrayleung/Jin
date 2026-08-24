import SwiftUI
import AppKit

/// Rendering policy for the Settings sidebar glyphs.
///
/// Native `Label(..., systemImage:)` inside a `.sidebar` `List` lets AppKit
/// own the tint. That path interpolates `controlAccentColor` when the
/// Settings window becomes key and replays SF Symbol appear / hierarchical
/// effects whenever `SettingsView` re-evaluates — both read as a one-frame
/// flash on every open and every section tap.
enum SettingsSidebarSymbolSupport {
    static let pointSize: CGFloat = 16
    static let weight: Font.Weight = .medium

    static let appleColorPreferencesChanged = Notification.Name(
        "AppleColorPreferencesChangedNotification"
    )

    static func suppressAnimations(_ transaction: inout Transaction) {
        transaction.animation = nil
        transaction.disablesAnimations = true
    }

    /// Never write `nil` back into the sidebar selection. A one-frame empty
    /// selection is enough for the list to restyle every glyph.
    static func sectionSelectionBinding(
        _ selectedSection: Binding<SettingsView.SettingsSection?>
    ) -> Binding<SettingsView.SettingsSection?> {
        Binding(
            get: { selectedSection.wrappedValue ?? .providers },
            set: { newValue in
                guard let newValue else { return }
                selectedSection.wrappedValue = newValue
            }
        )
    }

    static func accentColor(
        colorScheme: ColorScheme? = nil,
        contrast: ColorSchemeContrast? = nil
    ) -> Color {
        Color(nsColor: resolvedAccentNSColor(colorScheme: colorScheme, contrast: contrast))
    }

    static func appearance(
        for colorScheme: ColorScheme?,
        contrast: ColorSchemeContrast? = nil
    ) -> NSAppearance {
        let highContrast = contrast == .increased
        switch (colorScheme, highContrast) {
        case (.dark, true):
            return NSAppearance(named: .accessibilityHighContrastDarkAqua)
                ?? NSAppearance(named: .darkAqua)
                ?? NSAppearance(named: .aqua)!
        case (.dark, false):
            return NSAppearance(named: .darkAqua) ?? NSAppearance(named: .aqua)!
        case (_, true):
            return NSAppearance(named: .accessibilityHighContrastAqua)
                ?? NSAppearance(named: .aqua)!
        default:
            return NSAppearance(named: .aqua)!
        }
    }

    /// Snapshot the current accent into a component color. Catalog accents
    /// (`controlAccentColor`, SwiftUI `.accentColor`) are emphasis-aware and
    /// animate gray → blue when the window becomes key.
    ///
    /// Resolve against a named appearance instead of `NSApp` so XCTest and
    /// the Settings window's own color scheme stay well-defined.
    static func resolvedAccentNSColor(
        appearance: NSAppearance? = nil,
        colorScheme: ColorScheme? = nil,
        contrast: ColorSchemeContrast? = nil
    ) -> NSColor {
        let drawingAppearance = appearance ?? Self.appearance(for: colorScheme, contrast: contrast)
        var red: CGFloat = 0
        var green: CGFloat = 0.478
        var blue: CGFloat = 1
        var alpha: CGFloat = 1

        drawingAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.controlAccentColor.usingColorSpace(.sRGB)
                ?? NSColor.systemBlue.usingColorSpace(.sRGB)
            if let color {
                red = color.redComponent
                green = color.greenComponent
                blue = color.blueComponent
                alpha = color.alphaComponent
            }
        }

        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
