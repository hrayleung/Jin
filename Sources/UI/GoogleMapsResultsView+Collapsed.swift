import SwiftUI

extension GoogleMapsResultsView {
    func collapsedRow(content: MapsContent) -> some View {
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

    func placeNamePills(places: [MapsPlace]) -> some View {
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
}
