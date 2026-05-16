import SwiftUI

enum JinSurfaceVariant {
    case neutral
    case raised
    case selected
    case subtle
    case subtleStrong
    case accent
    case tool
    case outlined

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
        case .outlined:
            return Color.clear
        }
    }

    fileprivate var stroke: Color {
        switch self {
        case .selected:
            return JinSemanticColor.selectedStroke
        case .neutral, .accent, .tool:
            return Color.clear
        case .raised, .subtle, .subtleStrong, .outlined:
            return JinSemanticColor.borderSubtle
        }
    }

    fileprivate var lineWidth: CGFloat {
        switch self {
        case .selected:
            return JinStrokeWidth.regular
        case .neutral, .accent, .tool:
            return 0
        case .raised, .subtle, .subtleStrong, .outlined:
            return JinStrokeWidth.hairline
        }
    }

    fileprivate var shadowColor: Color {
        switch self {
        case .raised:
            return JinSemanticColor.shadowSubtle
        default:
            return Color.clear
        }
    }

    fileprivate var shadowRadius: CGFloat {
        switch self {
        case .raised:
            return 8
        default:
            return 0
        }
    }

    fileprivate var shadowYOffset: CGFloat {
        switch self {
        case .raised:
            return 1
        default:
            return 0
        }
    }
}

extension View {
    func jinSurface(_ variant: JinSurfaceVariant, cornerRadius: CGFloat = JinRadius.medium) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                shape
                    .fill(variant.fill)
                    .shadow(
                        color: variant.shadowColor,
                        radius: variant.shadowRadius,
                        x: 0,
                        y: variant.shadowYOffset
                    )
            )
            .overlay(
                shape.stroke(variant.stroke, lineWidth: variant.lineWidth)
            )
    }

    func jinTagStyle(foreground: Color = .secondary) -> some View {
        modifier(JinTagStyleModifier(foreground: foreground))
    }

    func jinInfoCallout() -> some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JinSemanticColor.textTertiary)
                .padding(.top, 1)

            self
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JinSpacing.xSmall)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    func jinTextEditorField(cornerRadius: CGFloat = JinRadius.small) -> some View {
        modifier(JinTextEditorFieldModifier(cornerRadius: cornerRadius))
    }

    func jinInlineErrorText() -> some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(.top, 1)
            self
                .font(.caption)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JinSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    func jinCardPadding() -> some View {
        self.padding(JinSpacing.medium)
    }

    /// Small-caps section header used to flatten card-in-card nesting. Pairs
    /// with a single 0.5pt divider underneath; replaces "header bg + body bg
    /// + border" code-block chrome.
    func jinSectionHeader() -> some View {
        self
            .font(.system(size: 11, weight: .semibold, design: .default))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(JinSemanticColor.textSecondary)
    }
}

private struct JinTagStyleModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let foreground: Color

    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
            )
            // Tags are interior elements — no stroke. Restored only under
            // increased-contrast a11y mode where fill alone isn't enough.
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        contrast == .increased ? JinSemanticColor.borderEmphasized : Color.clear,
                        lineWidth: JinStrokeWidth.hairline
                    )
            )
    }
}

private struct JinTextEditorFieldModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(JinSpacing.small)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(JinSemanticColor.textSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: JinStrokeWidth.hairline)
            )
    }

    private var borderColor: Color {
        contrast == .increased
            ? JinSemanticColor.borderEmphasized
            : JinSemanticColor.borderSubtle
    }
}
