import SwiftUI

struct SearchActivityTimelineView: View {
    let activities: [SearchActivity]
    let isStreaming: Bool
    let providerLabel: String?
    let modelLabel: String?
    var onExpansionChanged: () -> Void = {}

    init(
        activities: [SearchActivity],
        isStreaming: Bool,
        providerLabel: String? = nil,
        modelLabel: String? = nil,
        onExpansionChanged: @escaping () -> Void = {}
    ) {
        self.activities = activities
        self.isStreaming = isStreaming
        self.providerLabel = providerLabel
        self.modelLabel = modelLabel
        self.onExpansionChanged = onExpansionChanged
    }

    var body: some View {
        if let routedContent = SearchActivityTimelineSupport.routedContent(from: activities) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                if routedContent.showsMapsPanel {
                    GoogleMapsResultsView(
                        activities: activities,
                        isStreaming: isStreaming,
                        providerLabel: providerLabel,
                        modelLabel: modelLabel,
                        onExpansionChanged: onExpansionChanged
                    )
                }

                if let webContent = routedContent.webContent {
                    SearchActivityWebTimelinePanel(
                        content: webContent,
                        isStreaming: isStreaming,
                        contextLabel: contextLabel,
                        onExpansionChanged: onExpansionChanged
                    )
                }
            }
        }
    }

    // MARK: - Derived Content

    private var contextLabel: String? {
        SearchActivityTimelineSupport.contextLabel(
            providerLabel: providerLabel,
            modelLabel: modelLabel
        )
    }
}
