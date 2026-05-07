import Collections
import Foundation

enum SearchActivityPresentationBuilder {
    struct Output: Equatable {
        let queries: [String]
        let sources: [SearchSource]
    }

    static func build(from activities: [SearchActivity]) -> Output {
        var queriesByKey: OrderedDictionary<String, String> = [:]
        var sourceByID: OrderedDictionary<String, SearchSource> = [:]

        for activity in activities {
            appendQueries(from: activity, to: &queriesByKey)
            appendSources(from: activity, to: &sourceByID)
        }

        return Output(
            queries: Array(queriesByKey.values),
            sources: Array(sourceByID.values)
        )
    }

    private static func appendQueries(
        from activity: SearchActivity,
        to queriesByKey: inout OrderedDictionary<String, String>
    ) {
        func appendQuery(_ raw: String) {
            guard let normalized = raw.trimmedNonEmpty else { return }
            let key = normalized.lowercased()
            if queriesByKey[key] == nil {
                queriesByKey[key] = normalized
            }
        }

        for query in activity.stringArrayArgument("queries") {
            appendQuery(query)
        }
        if let query = activity.stringArgument("query") {
            appendQuery(query)
        }
    }

    private static func appendSources(
        from activity: SearchActivity,
        to sourceByID: inout OrderedDictionary<String, SearchSource>
    ) {
        for sourceArgument in activity.presentationSourceArguments {
            upsertSource(sourceArgument, into: &sourceByID)
        }
    }

    private static func upsertSource(
        _ sourceArgument: SearchSourceArgument,
        into sourceByID: inout OrderedDictionary<String, SearchSource>
    ) {
        guard let source = SearchSource(
            rawURL: sourceArgument.url,
            title: sourceArgument.title,
            previewText: sourceArgument.previewText,
            kind: sourceArgument.kind,
            mapsPlaceID: sourceArgument.mapsPlaceID
        ) else {
            return
        }

        if let existing = sourceByID[source.id] {
            sourceByID[source.id] = existing.merged(
                withTitle: source.title,
                previewText: source.previewText,
                kind: source.kind,
                mapsPlaceID: source.mapsPlaceID
            )
            return
        }
        sourceByID[source.id] = source
    }
}
