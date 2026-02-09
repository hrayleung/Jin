import SwiftUI

enum JinSurfaceVariant {
    case neutral
    case raised
    case selected
    case subtle
    case subtleStrong
    case accent
    case tool

    fileprivate var fill: Color {
        switch self {
        case .neutral:
            return JinSemanticColor.surface
        case .raised:
            return JinSemanticColor.raisedSurface
        case .selected:
            return JinSemanticColor.selectedSurface
        case .subtle:
            return JinSemanticColor.subtleSurface
        case .subtleStrong:
            return JinSemanticColor.subtleSurfaceStrong
        case .accent:
            return JinSemanticColor.accentSurface
        case .tool:
            return JinSemanticColor.surface.opacity(0.5)
        }
    }

    fileprivate var stroke: Color {
        switch self {
        case .selected:
            return JinSemanticColor.selectedStroke
        case .neutral, .accent, .tool:
            return Color.clear
        default:
            return JinSemanticColor.separator.opacity(0.5)
        }
    }

    fileprivate var lineWidth: CGFloat {
        switch self {
        case .selected:
            return JinStrokeWidth.regular
        case .neutral, .accent, .tool:
            return 0
        default:
            return JinStrokeWidth.hairline
        }
    }
}

struct JinIconButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var accentColor: Color = .accentColor

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
            .background(
                Circle()
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            )
            .overlay(
                Circle()
                    .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isActive {
            return accentColor.opacity(isPressed ? 0.28 : 0.18)
        }
        return JinSemanticColor.subtleSurface.opacity(isPressed ? 1 : 0.75)
    }
}

extension View {
    func jinSurface(_ variant: JinSurfaceVariant, cornerRadius: CGFloat = JinRadius.medium) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(variant.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(variant.stroke, lineWidth: variant.lineWidth)
            )
    }

    func jinTagStyle(foreground: Color = .secondary) -> some View {
        self
            .font(.caption2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.6), lineWidth: JinStrokeWidth.hairline)
            )
    }

    func jinInfoCallout() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
    }

    func jinCardPadding() -> some View {
        self.padding(JinSpacing.medium)
    }
}
