import Foundation

struct SearchActivityPresentation: Equatable {
    enum DisplayKind: Equatable {
        case web
        case x
        case maps
        case webAndX
        case mixed

        var sectionTitle: String {
            switch self {
            case .web:
                return "Web Search"
            case .x:
                return "X Search"
            case .maps:
                return "Google Maps"
            case .webAndX:
                return "Web + X"
            case .mixed:
                return "Search & Maps"
            }
        }

        var summarySystemImage: String {
            switch self {
            case .web:
                return "magnifyingglass"
            case .x:
                return "at"
            case .maps:
                return "map"
            case .webAndX:
                return "magnifyingglass"
            case .mixed:
                return "map.circle"
            }
        }

        func sourceSummaryText(count: Int) -> String {
            switch self {
            case .web, .x, .webAndX:
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
        let hasXSources = sources.contains(where: { $0.kind.isXTwitter })
        let hasWebSources = sources.contains(where: { $0.kind == .web })
        if hasMapsSources {
            return (hasWebSources || hasXSources) ? .mixed : .maps
        }
        if hasWebSources && hasXSources {
            return .webAndX
        }
        if hasXSources {
            return .x
        }
        return .web
    }
}
