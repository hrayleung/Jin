import SwiftUI
#if os(macOS)
import AppKit
#endif

enum JinTypography {
    static let systemFontPreferenceValue = ""
    static let defaultFontDisplayName = "System Default"

    static let defaultChatMessageScale = 1.15
    static let chatMessageScaleRange: ClosedRange<Double> = 0.85...1.50
    static let chatMessageScaleStep = 0.05

    static let availableFontFamilies: [String] = {
        #if os(macOS)
        let families = NSFontManager.shared.availableFontFamilies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(families)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        #else
        return []
        #endif
    }()

    static func normalizedFontPreference(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return systemFontPreferenceValue }

        if let exactMatch = availableFontFamilies.first(where: {
            $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return exactMatch
        }
        return trimmed
    }

    static func displayName(for preferenceValue: String) -> String {
        let normalized = normalizedFontPreference(preferenceValue)
        guard !normalized.isEmpty else { return defaultFontDisplayName }

        if availableFontFamilySet.contains(normalized) {
            return normalized
        }
        return "\(normalized) (Unavailable)"
    }

    static func clampedChatMessageScale(_ value: Double) -> Double {
        min(max(value, chatMessageScaleRange.lowerBound), chatMessageScaleRange.upperBound)
    }

    static func appFont(familyPreference: String) -> Font {
        let size = preferredBodyPointSize
        if let custom = customFontIfAvailable(familyPreference: familyPreference, size: size) {
            return custom
        }
        return .system(size: size, weight: .regular, design: .default)
    }

    static func chatBodyFont(appFamilyPreference: String, scale: Double) -> Font {
        let size = chatBodyPointSize(scale: scale)
        if let custom = customFontIfAvailable(familyPreference: appFamilyPreference, size: size) {
            return custom
        }
        return .system(size: size, weight: .regular, design: .default)
    }

    static func chatCodeFont(codeFamilyPreference: String, scale: Double) -> Font {
        let size = chatBodyPointSize(scale: scale)
        if let custom = customFontIfAvailable(familyPreference: codeFamilyPreference, size: size) {
            return custom
        }
        return .system(size: size, weight: .regular, design: .monospaced)
    }

    static func chatBodyPointSize(scale: Double) -> CGFloat {
        preferredBodyPointSize * clampedScaleCGFloat(scale)
    }

    static func pickerPreviewFont(familyName: String?) -> Font {
        let size: CGFloat = 13
        if let familyName,
           let custom = customFontIfAvailable(familyPreference: familyName, size: size) {
            return custom
        }
        return .system(size: size, weight: .regular, design: .default)
    }

    private static let availableFontFamilySet = Set(availableFontFamilies)

    private static func resolvedFamilyName(from preferenceValue: String) -> String? {
        let normalized = normalizedFontPreference(preferenceValue)
        guard !normalized.isEmpty else { return nil }
        guard availableFontFamilySet.contains(normalized) else { return nil }
        return normalized
    }

    private static func customFontIfAvailable(familyPreference: String, size: CGFloat) -> Font? {
        guard let familyName = resolvedFamilyName(from: familyPreference) else { return nil }

        #if os(macOS)
        if let font = NSFontManager.shared.font(withFamily: familyName, traits: [], weight: 5, size: size) {
            return Font(font)
        }

        if let font = NSFont(name: familyName, size: size) {
            return Font(font)
        }
        #endif

        return nil
    }

    private static var preferredBodyPointSize: CGFloat {
        #if os(macOS)
        return NSFont.preferredFont(forTextStyle: .body).pointSize
        #else
        return 17
        #endif
    }

    private static func clampedScaleCGFloat(_ value: Double) -> CGFloat {
        CGFloat(clampedChatMessageScale(value))
    }
}
