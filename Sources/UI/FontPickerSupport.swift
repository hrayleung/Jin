import Foundation

enum FontPickerSupport {
    static let systemDefaultPreviewText = "Use the system default font."
    static let fontPreviewText = "The quick brown fox jumps over 0123456789."

    static func trimmedSearchText(_ searchText: String) -> String {
        searchText.trimmedNonEmpty ?? ""
    }

    static func filteredFamilies(_ families: [String], searchText: String) -> [String] {
        let query = trimmedSearchText(searchText)
        guard !query.isEmpty else { return families }

        return families.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    static func shouldShowSystemDefaultRow(searchText: String) -> Bool {
        trimmedSearchText(searchText).isEmpty
    }

    static func emptySearchText(searchText: String, filteredFamilies: [String]) -> String? {
        let query = trimmedSearchText(searchText)
        guard !query.isEmpty, filteredFamilies.isEmpty else { return nil }
        return query
    }

    static func normalizedSelection(_ selectedFontFamily: String) -> String {
        JinTypography.normalizedFontPreference(selectedFontFamily)
    }

    static func isSystemDefaultSelected(selectedFontFamily: String) -> Bool {
        normalizedSelection(selectedFontFamily).isEmpty
    }

    static func isFamilySelected(_ family: String, selectedFontFamily: String) -> Bool {
        normalizedSelection(selectedFontFamily) == family
    }

    static func selectedFontFamily(_ family: String) -> String {
        JinTypography.normalizedFontPreference(family)
    }
}
