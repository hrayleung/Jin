import Foundation

struct SearchActivityPresentation: Equatable {
    enum DisplayKind: Equatable {
        case web
        case maps
        case mixed

        var sectionTitle: String {
            switch self {
            case .web:
                return "Web Search"
            case .maps:
                return "Google Maps"
            case .mixed:
                return "Search & Maps"
            }
        }

        var summarySystemImage: String {
            switch self {
            case .web:
                return "magnifyingglass"
            case .maps:
                return "map"
            case .mixed:
                return "map.circle"
            }
        }

        func sourceSummaryText(count: Int) -> String {
            switch self {
            case .web:
                return "Browsed \(count) link" + (count == 1 ? "" : "s")
            case .maps:
                return "Cited \(count) place source" + (count == 1 ? "" : "s")
            case .mixed:
                return "Browsed \(count) grounded source" + (count == 1 ? "" : "s")
            }
        }
    }

    let queries: [String]
    let sources: [SearchSource]
    let displayKind: DisplayKind

    var sectionTitle: String { displayKind.sectionTitle }
    var summarySystemImage: String { displayKind.summarySystemImage }
    var sourceSummaryText: String { displayKind.sourceSummaryText(count: sources.count) }

    init(activities: [SearchActivity]) {
        let output = SearchActivityPresentationBuilder.build(from: activities)
        queries = output.queries
        sources = output.sources
        displayKind = Self.displayKind(for: sources)
    }

    private static func displayKind(for sources: [SearchSource]) -> DisplayKind {
        let hasMapsSources = sources.contains(where: { $0.kind.isGoogleMaps })
        let hasWebSources = sources.contains(where: { !$0.kind.isGoogleMaps })
        switch (hasMapsSources, hasWebSources) {
        case (true, true):
            return .mixed
        case (true, false):
            return .maps
        default:
            return .web
        }
    }
}
