import SwiftUI

struct ArtifactTypeBadge: View {
    let contentType: ArtifactContentType

    var body: some View {
        Text(contentType.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
            )
    }
}

struct MessageArtifactCardView: View {
    let artifact: RenderedArtifactVersion
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: JinSpacing.small) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(artifactAccentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: artifactIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(artifactAccentColor)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        ArtifactTypeBadge(contentType: artifact.contentType)

                        Text("Artifact")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Text("Open")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(artifactAccentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(artifactAccentColor.opacity(isHovered ? 0.18 : 0.1))
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 400, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(JinSemanticColor.subtleSurface.opacity(isHovered ? 1 : 0.7))
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: JinRadius.small,
                    bottomLeadingRadius: JinRadius.small,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(artifactAccentColor)
                .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(
                        artifactAccentColor.opacity(isHovered ? 0.25 : 0.1),
                        lineWidth: JinStrokeWidth.hairline
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Open \(artifact.title)")
    }

    private var artifactAccentColor: Color {
        switch artifact.contentType {
        case .react:
            return Color(red: 0.55, green: 0.68, blue: 0.78)
        case .html:
            return Color(red: 0.75, green: 0.58, blue: 0.50)
        case .echarts:
            return Color(red: 0.55, green: 0.70, blue: 0.60)
        }
    }

    private var artifactIconName: String {
        switch artifact.contentType {
        case .react:
            return "atom"
        case .html:
            return "globe"
        case .echarts:
            return "chart.bar.xaxis"
        }
    }
}
