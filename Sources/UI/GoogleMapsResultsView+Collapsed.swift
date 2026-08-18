import SwiftUI

extension GoogleMapsResultsView {
    func collapsedRow(content: MapsContent) -> some View {
        Button {
            toggleExpanded()
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .frame(width: 16, height: 16)

                if content.places.isEmpty {
                    Text("Places")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    placeNamePills(places: content.places)
                }

                Spacer(minLength: 0)

                // Maps previously used up/down chevrons on the trailing edge;
                // rotate the shared right-chevron so expand motion matches
                // web-search / thinking disclosures.
                JinDisclosureChevron(
                    isExpanded: isExpanded,
                    font: .caption2.weight(.semibold),
                    foregroundStyle: Color.secondary
                )
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Places"))
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Hides map results" : "Shows map results"))
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
