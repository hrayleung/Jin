import SwiftUI

extension GoogleMapsResultsView {
    func expandedPanel(content: MapsContent) -> some View {
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

    func panelHeader(content: MapsContent) -> some View {
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

    func mapsQueryChips(queries: [String]) -> some View {
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

    func placeListSection(places: [MapsPlace]) -> some View {
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
}
