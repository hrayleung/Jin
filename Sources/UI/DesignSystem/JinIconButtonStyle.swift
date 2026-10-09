import SwiftUI

struct JinIconButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var accentColor: Color = .accentColor
    var showBackground: Bool = true
    var size: CGFloat = JinControlMetrics.iconButtonHitSize

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, style: self)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        let style: JinIconButtonStyle

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(width: style.size, height: style.size)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(backgroundFill)
                }
                .overlay {
                    if contrast == .increased, style.showBackground || style.isActive {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(JinThemeResolver.borderHairline(contrast: contrast), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovered = $0 }
        }

        private var backgroundFill: Color {
            if style.isActive {
                return style.accentColor.opacity(configuration.isPressed ? 0.22 : 0.12)
            }
            if isEnabled, configuration.isPressed || isHovered {
                return JinSemanticColor.hoverFill.opacity(configuration.isPressed ? 1 : 0.75)
            }
            return style.showBackground ? JinSemanticColor.controlFill : .clear
        }
    }
}
