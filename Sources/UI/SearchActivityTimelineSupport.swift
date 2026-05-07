import Foundation

enum SearchActivityTimelineSupport {
    struct ViewContent {
        let presentation: SearchActivityPresentation
        let hasRunningActivity: Bool
    }

    struct RoutedContent {
        let showsMapsPanel: Bool
        let webContent: ViewContent?
    }

    static func routedContent(from activities: [SearchActivity]) -> RoutedContent? {
        guard !activities.isEmpty else { return nil }

        let content = buildContent(from: activities)
        let routeKinds = RouteKinds(sources: content.presentation.sources)

        return RoutedContent(
            showsMapsPanel: routeKinds.hasMaps,
            webContent: webPanelContent(for: routeKinds, from: activities, fallback: content)
        )
    }

    static func buildContent(from activities: [SearchActivity]) -> ViewContent {
        let orderedActivities = orderedActivities(activities)
        let hasRunningActivity = orderedActivities.contains(where: isRunningActivity)

        return ViewContent(
            presentation: SearchActivityPresentation(activities: orderedActivities),
            hasRunningActivity: hasRunningActivity
        )
    }

    static func orderedActivities(_ activities: [SearchActivity]) -> [SearchActivity] {
        activities
            .enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element
                let right = rhs.element

                if left.sequenceNumber != right.sequenceNumber {
                    return (left.sequenceNumber ?? Int.max) < (right.sequenceNumber ?? Int.max)
                }
                if left.outputIndex != right.outputIndex {
                    return (left.outputIndex ?? Int.max) < (right.outputIndex ?? Int.max)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func isRunningActivity(_ activity: SearchActivity) -> Bool {
        switch activity.status {
        case .inProgress, .searching:
            return true
        case .completed, .failed, .unknown:
            return false
        }
    }

    static func isMapsOpenPage(_ activity: SearchActivity) -> Bool {
        guard activity.type == ActivityType.openPage else { return false }
        return activity.sourceKindArgument.isGoogleMaps
    }

    static func isSearchActivity(_ activity: SearchActivity) -> Bool {
        activity.type == ActivityType.search || activity.type == ActivityType.searching
    }

    private static func isWebPanelActivity(_ activity: SearchActivity) -> Bool {
        !isMapsOpenPage(activity) && !isSearchActivity(activity)
    }

    private static func webPanelContent(
        for routeKinds: RouteKinds,
        from activities: [SearchActivity],
        fallback content: ViewContent
    ) -> ViewContent? {
        if routeKinds.hasWeb {
            return routeKinds.hasMaps
                ? buildContent(from: activities.filter(isWebPanelActivity))
                : content
        }

        return routeKinds.hasMaps ? nil : content
    }

    static func contextLabel(providerLabel: String?, modelLabel: String?) -> String? {
        let provider = providerLabel?.trimmedNonEmpty
        let model = modelLabel?.trimmedNonEmpty

        if let provider, let model {
            return "\(provider) / \(model)"
        }
        return model
    }

    private struct RouteKinds {
        let hasMaps: Bool
        let hasWeb: Bool

        init(sources: [SearchSource]) {
            hasMaps = sources.contains { $0.kind.isGoogleMaps }
            hasWeb = sources.contains { !$0.kind.isGoogleMaps }
        }
    }

    private enum ActivityType {
        static let openPage = "open_page"
        static let search = "search"
        static let searching = "searching"
    }
}
