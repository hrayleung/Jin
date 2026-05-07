import SwiftUI

struct MapsPlaceRowView: View {
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
