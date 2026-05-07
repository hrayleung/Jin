import SwiftUI

struct GoogleMapsLocationBias: Equatable {
    let latitude: Double
    let longitude: Double
}

private struct GoogleMapsLocationBiasKey: EnvironmentKey {
    static let defaultValue: GoogleMapsLocationBias? = nil
}

extension EnvironmentValues {
    var googleMapsLocationBias: GoogleMapsLocationBias? {
        get { self[GoogleMapsLocationBiasKey.self] }
        set { self[GoogleMapsLocationBiasKey.self] = newValue }
    }
}

enum MapsLayout {
    static let initialVisiblePlaces = 5
    static let mapHeight: CGFloat = 260
}

struct GoogleMapsResultsView: View {
    let activities: [SearchActivity]
    let isStreaming: Bool
    let providerLabel: String?
    let modelLabel: String?

    @Environment(\.googleMapsLocationBias) var locationBias
    @State var isExpanded = false
    @State var showAllPlaces = false

    var body: some View {
        let content = extractContent()

        if !content.places.isEmpty || !content.queries.isEmpty {
            VStack(alignment: .leading, spacing: isExpanded ? JinSpacing.small : 0) {
                collapsedRow(content: content)

                if isExpanded {
                    expandedPanel(content: content)
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
    }
}

struct MapsContent {
    let queries: [String]
    let places: [MapsPlace]
    let hasRunningActivity: Bool
}

struct MapsPlace: Identifiable {
    let id: String
    let name: String
    let urlString: String
    let placeID: String?
}

enum MapsDesign {
    static let accentColor = Color(red: 0.20, green: 0.66, blue: 0.33)
    static let pinColors: [Color] = [
        Color(red: 0.20, green: 0.66, blue: 0.33),
        Color(red: 0.26, green: 0.52, blue: 0.96),
        Color(red: 0.92, green: 0.26, blue: 0.21),
        Color(red: 1.00, green: 0.60, blue: 0.00),
        Color(red: 0.61, green: 0.15, blue: 0.69),
        Color(red: 0.00, green: 0.74, blue: 0.83),
        Color(red: 0.80, green: 0.26, blue: 0.60),
        Color(red: 0.47, green: 0.33, blue: 0.28),
    ]

    static func pinColor(for index: Int) -> Color {
        pinColors[index % pinColors.count]
    }
}
