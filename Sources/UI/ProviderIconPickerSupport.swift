import Foundation

enum ProviderIconPickerSupport {
    static func normalizedIconID(_ id: String?) -> String? {
        id?.trimmedNonEmpty
    }

    static func activeIconID(selectedIconID: String?, defaultIconID: String?) -> String? {
        normalizedIconID(selectedIconID) ?? normalizedIconID(defaultIconID)
    }

    static func displayLabel(selectedIconID: String?, defaultIconID: String?) -> String {
        if let normalized = normalizedIconID(selectedIconID) {
            return normalized
        }

        if let normalizedDefault = normalizedIconID(defaultIconID) {
            return "Default (\(normalizedDefault))"
        }

        return "Choose..."
    }

    static func filteredIcons(from icons: [LobeProviderIcon], searchText: String) -> [LobeProviderIcon] {
        let query = searchText.trimmedLowercased
        guard !query.isEmpty else { return icons }

        return icons.filter { icon in
            icon.id.lowercased().contains(query) || icon.docsSlug.lowercased().contains(query)
        }
    }

    static func isDefaultSelected(_ iconID: String?) -> Bool {
        normalizedIconID(iconID) == nil
    }

    static func isSelected(icon: LobeProviderIcon, selectedIconID: String?) -> Bool {
        normalizedIconID(selectedIconID)?.caseInsensitiveCompare(icon.id) == .orderedSame
    }
}
