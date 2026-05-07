import Foundation

enum MCPIconPickerSupport {
    static func normalizedCustomIconID(_ id: String?, defaultIconID: String) -> String? {
        guard let trimmed = id?.trimmedNonEmpty else { return nil }
        if trimmed.caseInsensitiveCompare(defaultIconID) == .orderedSame {
            return nil
        }
        return trimmed
    }

    static func activeIconID(selectedIconID: String?, defaultIconID: String) -> String {
        normalizedCustomIconID(selectedIconID, defaultIconID: defaultIconID) ?? defaultIconID
    }

    static func displayLabel(selectedIconID: String?, defaultIconID: String) -> String {
        normalizedCustomIconID(selectedIconID, defaultIconID: defaultIconID) ?? "Default"
    }

    static func selectableIcons(from icons: [MCPIcon], defaultIconID: String) -> [MCPIcon] {
        icons.filter { icon in
            icon.id.caseInsensitiveCompare(defaultIconID) != .orderedSame
        }
    }

    static func filteredIcons(
        from icons: [MCPIcon],
        searchText: String,
        defaultIconID: String
    ) -> [MCPIcon] {
        let selectableIcons = selectableIcons(from: icons, defaultIconID: defaultIconID)
        guard let query = searchText.trimmedNonEmpty?.lowercased() else { return selectableIcons }

        return selectableIcons.filter { icon in
            icon.id.lowercased().contains(query)
        }
    }

    static func isDefaultSelected(_ iconID: String?, defaultIconID: String) -> Bool {
        normalizedCustomIconID(iconID, defaultIconID: defaultIconID) == nil
    }

    static func isSelected(icon: MCPIcon, selectedIconID: String?, defaultIconID: String) -> Bool {
        normalizedCustomIconID(selectedIconID, defaultIconID: defaultIconID)?
            .caseInsensitiveCompare(icon.id) == .orderedSame
    }
}
