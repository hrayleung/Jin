import SwiftUI

struct JinIconButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var accentColor: Color = .accentColor
    var showBackground: Bool = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
            .background {
                if showBackground {
                    Circle()
                        .fill(backgroundFill(isPressed: configuration.isPressed))
                }
            }
            .overlay {
                if showBackground {
                    Circle()
                        .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
                }
            }
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
