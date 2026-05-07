import Foundation

extension GoogleMapsResultsView {
    func extractContent() -> MapsContent {
        let sorted = activities
            .enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element
                let r = rhs.element
                if l.sequenceNumber != r.sequenceNumber {
                    return (l.sequenceNumber ?? Int.max) < (r.sequenceNumber ?? Int.max)
                }
                if l.outputIndex != r.outputIndex {
                    return (l.outputIndex ?? Int.max) < (r.outputIndex ?? Int.max)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var queries: [String] = []
        var queryKeys: Set<String> = []
        var places: [MapsPlace] = []
        var placeKeys: Set<String> = []

        let hasRunningActivity = sorted.contains { activity in
            switch activity.status {
            case .inProgress, .searching: return true
            case .completed, .failed, .unknown: return false
            }
        }

        for activity in sorted {
            if activity.type == "search" || activity.type == "searching" {
                if let query = stringArg(activity, "query"),
                   queryKeys.insert(query.lowercased()).inserted {
                    queries.append(query)
                }
                for query in stringArrayArg(activity, "queries") {
                    if queryKeys.insert(query.lowercased()).inserted {
                        queries.append(query)
                    }
                }
            }

            if activity.type == "open_page",
               isMapsActivity(activity) {
                if let place = extractPlace(from: activity),
                   placeKeys.insert(place.id).inserted {
                    places.append(place)
                }
            }
        }

        return MapsContent(queries: queries, places: places, hasRunningActivity: hasRunningActivity)
    }

    func isMapsActivity(_ activity: SearchActivity) -> Bool {
        let sourceKind = (activity.arguments["sourceKind"]?.value as? String)?.lowercased()
        return sourceKind == "google_maps"
    }

    func extractPlace(from activity: SearchActivity) -> MapsPlace? {
        guard let urlString = stringArg(activity, "url") else { return nil }
        let name = stringArg(activity, "title") ?? urlString
        let placeID = stringArg(activity, "mapsPlaceID")

        let id = urlString.lowercased()
            .trimmed

        return MapsPlace(
            id: id,
            name: name,
            urlString: urlString,
            placeID: placeID
        )
    }

    func stringArg(_ activity: SearchActivity, _ key: String) -> String? {
        guard let value = activity.arguments[key]?.value as? String else { return nil }
        return value.trimmedNonEmpty
    }

    func stringArrayArg(_ activity: SearchActivity, _ key: String) -> [String] {
        if let values = activity.arguments[key]?.value as? [String] {
            return values.compactMap(\.trimmedNonEmpty)
        }
        if let values = activity.arguments[key]?.value as? [Any] {
            return values.compactMap { value in
                guard let string = value as? String else { return nil }
                return string.trimmedNonEmpty
            }
        }
        return []
    }
}
