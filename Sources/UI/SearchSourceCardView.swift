import AppKit
import SwiftUI

struct SearchSourceCardView: View {
    private enum Layout {
        static let cardWidth: CGFloat = 230
        static let cardHeight: CGFloat = 138
        static let previewLineLimit = 5
    }

    let presentation: SearchSource.RenderPresentation
    @State private var isHovered = false

    var body: some View {
        Group {
            if let destination = presentation.openURL {
                Link(destination: destination) {
                    cardBody
                }
                .buttonStyle(.plain)
            } else {
                cardBody
            }
        }
        .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .topLeading)
        .jinSurface(.neutral, cornerRadius: JinRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .stroke(
                    isHovered ? JinSemanticColor.selectedStroke : JinSemanticColor.separator.opacity(0.42),
                    lineWidth: isHovered ? JinStrokeWidth.regular : JinStrokeWidth.hairline
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1)
        .shadow(color: Color.black.opacity(isHovered ? 0.1 : 0), radius: 10, x: 0, y: 5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            HStack(alignment: .top, spacing: JinSpacing.xSmall) {
                Text(presentation.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: presentation.kind.isGoogleMaps ? "map.fill" : "arrow.up.right.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(presentation.kind.isGoogleMaps ? Color.accentColor : Color.secondary)
            }

            Text(presentation.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(Layout.previewLineLimit)
                .lineSpacing(1)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            HStack(spacing: JinSpacing.xSmall) {
                SearchSourceAvatarView(
                    host: presentation.host,
                    fallbackText: presentation.hostDisplayInitial,
                    kind: presentation.kind,
                    size: 16
                )
                Text(presentation.hostDisplay)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("Open")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
}

struct SearchSourceAvatarView: View {
    let host: String
    let fallbackText: String
    let kind: SearchSourceKind
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            if kind.isGoogleMaps {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))

                Image(systemName: "map.fill")
                    .font(.system(size: max(9, size - 10), weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Circle()
                    .fill(JinSemanticColor.surface)

                WebsiteFaviconView(
                    host: host,
                    fallbackText: fallbackText,
                    iconSize: max(12, size - 8)
                )
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(JinSemanticColor.separator.opacity(0.6), lineWidth: JinStrokeWidth.hairline)
        )
    }
}

struct WebsiteFaviconView: View {
    let host: String
    let fallbackText: String
    let iconSize: CGFloat
    @State private var faviconImage: NSImage?

    var body: some View {
        Group {
            if let faviconImage {
                Image(nsImage: faviconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else {
                fallbackBadge
            }
        }
        .task(id: host) {
            await MainActor.run { faviconImage = nil }
            let image = await FaviconLoader.shared.favicon(for: host)
            guard !Task.isCancelled else { return }
            await MainActor.run { faviconImage = image }
        }
    }

    private var fallbackBadge: some View {
        let hue = stableHue(for: host)
        let color = Color(hue: hue, saturation: 0.4, brightness: 0.9)
        return Text(fallbackText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .frame(width: iconSize, height: iconSize)
            .background(
                Circle()
                    .fill(color.opacity(0.85))
            )
    }

    private func stableHue(for input: String) -> Double {
        var hash: UInt32 = 5381
        for byte in input.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return Double(hash % 360) / 360.0
    }
}
