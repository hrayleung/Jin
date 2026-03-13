import SwiftUI
import WebKit

// MARK: - Environment Key

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

// MARK: - Main View

private enum MapsLayout {
    static let initialVisiblePlaces = 5
    static let mapHeight: CGFloat = 260
}

struct GoogleMapsResultsView: View {
    let activities: [SearchActivity]
    let isStreaming: Bool
    let providerLabel: String?
    let modelLabel: String?

    @Environment(\.googleMapsLocationBias) private var locationBias
    @State private var isExpanded = false
    @State private var showAllPlaces = false

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

    // MARK: - Collapsed Row

    private func collapsedRow(content: MapsContent) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                if content.places.isEmpty {
                    Text("Places")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    placeNamePills(places: content.places)
                }

                Spacer(minLength: 0)

                if isStreaming && content.hasRunningActivity {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeNamePills(places: [MapsPlace]) -> some View {
        HStack(spacing: JinSpacing.xSmall) {
            ForEach(Array(places.prefix(3)), id: \.id) { place in
                HStack(spacing: 3) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(MapsDesign.accentColor)
                    Text(place.name)
                        .lineLimit(1)
                }
                .jinTagStyle()
            }

            if places.count > 3 {
                Text("+\(places.count - 3)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Expanded Panel

    private func expandedPanel(content: MapsContent) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            panelHeader(content: content)

            if !content.queries.isEmpty {
                mapsQueryChips(queries: content.queries)
            }

            if let embedURL = googleMapsEmbedURL(content: content) {
                ZStack(alignment: .bottom) {
                    GoogleMapsEmbedView(url: embedURL)
                        .frame(height: MapsLayout.mapHeight)

                    LinearGradient(
                        colors: [.clear, JinSemanticColor.subtleSurfaceStrong.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.4), lineWidth: JinStrokeWidth.hairline)
                )
            }

            if !content.places.isEmpty {
                placeListSection(places: content.places)
            } else {
                Text("Searching for places...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JinSpacing.small)
                    .padding(.vertical, 6)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, 2)
        .padding(.bottom, JinSpacing.xSmall)
    }

    private func panelHeader(content: MapsContent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small - 2) {
            Text("Places")
                .font(.headline)

            if let contextLabel {
                Text("(\(contextLabel))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let openURL = googleMapsOpenURL(content: content) {
                Link(destination: openURL) {
                    HStack(spacing: 3) {
                        Text("Google Maps")
                            .font(.caption.weight(.medium))
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mapsQueryChips(queries: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JinSpacing.small - 2) {
                ForEach(Array(queries.enumerated()), id: \.offset) { _, query in
                    HStack(spacing: JinSpacing.xSmall) {
                        Image(systemName: "location.magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(query)
                            .font(.subheadline)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, JinSpacing.small)
                    .padding(.vertical, 5)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func placeListSection(places: [MapsPlace]) -> some View {
        let visibleCount = showAllPlaces ? places.count : min(places.count, MapsLayout.initialVisiblePlaces)
        let hiddenCount = places.count - MapsLayout.initialVisiblePlaces

        return VStack(spacing: 0) {
            ForEach(Array(places.prefix(visibleCount).enumerated()), id: \.element.id) { index, place in
                MapsPlaceRowView(place: place, index: index + 1)

                if index < visibleCount - 1 {
                    Rectangle()
                        .fill(JinSemanticColor.separator.opacity(0.3))
                        .frame(height: JinStrokeWidth.hairline)
                        .padding(.leading, 46)
                }
            }

            if hiddenCount > 0 && !showAllPlaces {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllPlaces = true
                    }
                } label: {
                    HStack(spacing: JinSpacing.xSmall) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .bold))
                        Text("Show \(hiddenCount) more place\(hiddenCount == 1 ? "" : "s")")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, JinSpacing.small)
                }
                .buttonStyle(.plain)
            }

            if showAllPlaces && hiddenCount > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllPlaces = false
                    }
                } label: {
                    Text("Show less")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, JinSpacing.small - 2)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.35), lineWidth: JinStrokeWidth.hairline)
        )
    }

    // MARK: - URL Construction

    private func googleMapsEmbedURL(content: MapsContent) -> URL? {
        let locationSuffix: String
        if let bias = locationBias {
            locationSuffix = "/@\(bias.latitude),\(bias.longitude),14z"
        } else {
            locationSuffix = ""
        }

        if let query = content.queries.first {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
            return URL(string: "https://www.google.com/maps/search/\(encoded)\(locationSuffix)")
        }

        if let place = content.places.first {
            let encoded = place.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? place.name
            return URL(string: "https://www.google.com/maps/search/\(encoded)\(locationSuffix)")
        }

        return nil
    }

    private func googleMapsOpenURL(content: MapsContent) -> URL? {
        googleMapsEmbedURL(content: content)
    }

    // MARK: - Helpers

    private var contextLabel: String? {
        let provider = providerLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let provider, !provider.isEmpty, let model, !model.isEmpty {
            return "\(provider) / \(model)"
        }
        if let model, !model.isEmpty {
            return model
        }
        return nil
    }

    // MARK: - Data Extraction

    private func extractContent() -> MapsContent {
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
                for q in stringArrayArg(activity, "queries") {
                    if queryKeys.insert(q.lowercased()).inserted {
                        queries.append(q)
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

    private func isMapsActivity(_ activity: SearchActivity) -> Bool {
        let sourceKind = (activity.arguments["sourceKind"]?.value as? String)?.lowercased()
        return sourceKind == "google_maps"
    }

    private func extractPlace(from activity: SearchActivity) -> MapsPlace? {
        guard let urlString = stringArg(activity, "url") else { return nil }
        let name = stringArg(activity, "title") ?? urlString
        let placeID = stringArg(activity, "mapsPlaceID")

        let id = urlString.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return MapsPlace(
            id: id,
            name: name,
            urlString: urlString,
            placeID: placeID
        )
    }

    private func stringArg(_ activity: SearchActivity, _ key: String) -> String? {
        guard let value = activity.arguments[key]?.value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stringArrayArg(_ activity: SearchActivity, _ key: String) -> [String] {
        if let values = activity.arguments[key]?.value as? [String] {
            return values.compactMap { v in
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
        }
        if let values = activity.arguments[key]?.value as? [Any] {
            return values.compactMap { v in
                guard let s = v as? String else { return nil }
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
        }
        return []
    }
}

// MARK: - Data Models

private struct MapsContent {
    let queries: [String]
    let places: [MapsPlace]
    let hasRunningActivity: Bool
}

private struct MapsPlace: Identifiable {
    let id: String
    let name: String
    let urlString: String
    let placeID: String?
}

// MARK: - Design Constants

private enum MapsDesign {
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

// MARK: - Google Maps Embed (WKWebView)

private struct GoogleMapsEmbedView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Place Row

private struct MapsPlaceRowView: View {
    let place: MapsPlace
    let index: Int

    @State private var isHovered = false

    var body: some View {
        Group {
            if let url = URL(string: place.urlString) {
                Link(destination: url) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .padding(.leading, 0)
        .padding(.trailing, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .background(isHovered ? JinSemanticColor.subtleSurface : JinSemanticColor.surface.opacity(0.5))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            accentBar
                .padding(.trailing, JinSpacing.small)

            pinBadge
                .padding(.trailing, JinSpacing.small + 2)

            Text(place.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.4))
        }
    }

    private var accentBar: some View {
        let color = MapsDesign.pinColor(for: index - 1)
        return RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 3, height: 22)
    }

    private var pinBadge: some View {
        let color = MapsDesign.pinColor(for: index - 1)
        return Text("\(index)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(
                Circle().fill(color.opacity(0.12))
            )
    }
}
