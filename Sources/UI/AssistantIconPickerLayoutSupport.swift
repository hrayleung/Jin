import Foundation

enum AssistantIconPickerLayoutSupport {
    static func chunked<T>(_ values: [T], into size: Int) -> [[T]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: values.count, by: size).map {
            Array(values[$0..<Swift.min($0 + size, values.count)])
        }
    }

    static func trimmedSearchText(_ searchText: String) -> String {
        searchText.trimmedNonEmpty ?? ""
    }

    static func filteredSymbolCategories(
        _ categories: [AssistantIconCategory],
        searchText: String
    ) -> [AssistantIconCategory] {
        let query = trimmedSearchText(searchText)
        guard !query.isEmpty else { return categories }

        return categories.compactMap { category in
            if category.name.localizedStandardContains(query) {
                return category
            }

            let filteredIcons = category.icons.filter { icon in
                icon.localizedStandardContains(query)
            }
            guard !filteredIcons.isEmpty else { return nil }
            return AssistantIconCategory(name: category.name, icons: filteredIcons)
        }
    }
}
