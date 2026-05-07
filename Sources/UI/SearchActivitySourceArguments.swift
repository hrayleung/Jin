import Foundation

struct SearchSourceArgument {
    let url: String
    let title: String?
    let previewText: String?
    let kind: SearchSourceKind
    let mapsPlaceID: String?
}

extension SearchActivity {
    func stringArgument(_ key: String) -> String? {
        guard let value = arguments[key]?.value as? String else { return nil }
        return value.trimmedNonEmpty
    }

    func stringArrayArgument(_ key: String) -> [String] {
        if let values = arguments[key]?.value as? [String] {
            return values.compactMap { $0.trimmedNonEmpty }
        }

        if let values = arguments[key]?.value as? [Any] {
            return values.compactMap { ($0 as? String)?.trimmedNonEmpty }
        }

        return []
    }

    var sourcePreviewArgument: String? {
        SearchActivityArgumentValues.preferredPreviewValue(in: arguments.mapValues(\.value))
    }

    var sourceKindArgument: SearchSourceKind {
        SearchSourceKind(rawValueOrDefault: stringArgument("sourceKind"))
    }

    var sourceArguments: [SearchSourceArgument] {
        guard let value = arguments["sources"]?.value else { return [] }
        return SearchActivityArgumentValues.sourceDictionaries(from: value)
            .compactMap(SearchSourceArgument.init(dictionary:))
    }

    var presentationSourceArguments: [SearchSourceArgument] {
        var arguments = sourceArguments
        if let directSourceArgument {
            arguments.insert(directSourceArgument, at: 0)
        }
        return arguments
    }

    private var directSourceArgument: SearchSourceArgument? {
        guard let url = stringArgument("url") else { return nil }
        return SearchSourceArgument(
            url: url,
            title: stringArgument("title"),
            previewText: sourcePreviewArgument,
            kind: sourceKindArgument,
            mapsPlaceID: stringArgument("mapsPlaceID")
        )
    }
}

private extension SearchSourceArgument {
    init?(dictionary item: [String: Any]) {
        let nestedSource = item["source"] as? [String: Any]
        guard let url = SearchActivityArgumentValues.firstTrimmedString(
            for: ["url"],
            in: item,
            nested: nestedSource
        ) else {
            return nil
        }

        let title = SearchActivityArgumentValues.firstTrimmedString(for: ["title"], in: item, nested: nestedSource)
        let previewText = SearchActivityArgumentValues.preferredPreviewValue(in: item)
            ?? nestedSource.flatMap { SearchActivityArgumentValues.preferredPreviewValue(in: $0) }
        let sourceKind = SearchSourceKind(
            rawValueOrDefault: SearchActivityArgumentValues.sourceKindString(in: item, nested: nestedSource)
        )
        let mapsPlaceID = SearchActivityArgumentValues.firstTrimmedString(
            for: ["mapsPlaceID", "placeId", "place_id"],
            in: item,
            nested: nestedSource
        )

        self.init(
            url: url,
            title: title,
            previewText: previewText,
            kind: sourceKind,
            mapsPlaceID: mapsPlaceID
        )
    }
}

private enum SearchActivityArgumentValues {
    private static let previewKeys = [
        "snippet",
        "summary",
        "description",
        "preview",
        "excerpt",
        "cited_text",
        "citedText",
        "quote",
        "abstract"
    ]

    static func sourceDictionaries(from value: Any) -> [[String: Any]] {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }
    }

    static func firstTrimmedString(
        for keys: [String],
        in dictionary: [String: Any],
        nested: [String: Any]? = nil
    ) -> String? {
        firstTrimmedString(for: keys, in: dictionary)
            ?? nested.flatMap { firstTrimmedString(for: keys, in: $0) }
    }

    static func preferredPreviewValue(in dictionary: [String: Any]) -> String? {
        for key in previewKeys {
            if let value = (dictionary[key] as? String)?.trimmedNonEmpty {
                return value
            }
        }

        return nil
    }

    static func sourceKindString(in dictionary: [String: Any], nested: [String: Any]?) -> String? {
        firstString(for: ["sourceKind", "type"], in: dictionary)
            ?? nested.flatMap { firstString(for: ["sourceKind", "type"], in: $0) }
    }

    private static func firstTrimmedString(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = (dictionary[key] as? String)?.trimmedNonEmpty {
                return value
            }
        }

        return nil
    }

    private static func firstString(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }

        return nil
    }
}
