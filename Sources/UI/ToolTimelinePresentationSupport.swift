import SwiftUI

enum ToolTimelinePresentationSupport {
    enum StatusTone {
        case success
        case failure

        var color: Color {
            switch self {
            case .success:
                return Color(nsColor: .systemGreen)
            case .failure:
                return Color(nsColor: .systemOrange)
            }
        }

        var emphasizedColor: Color {
            switch self {
            case .success:
                return color.opacity(0.88)
            case .failure:
                return color.opacity(0.95)
            }
        }
    }

    struct StatusVisualStyle {
        let accent: Color
        let text: Color
        let nodeBackground: Color
        let nodeBorder: Color
        let glowColor: Color
    }

    static func terminalStatusStyle(for status: ToolCallExecutionStatus) -> StatusVisualStyle {
        switch status {
        case .running:
            return StatusVisualStyle(
                accent: .secondary,
                text: .secondary,
                nodeBackground: JinSemanticColor.subtleSurfaceStrong,
                nodeBorder: JinSemanticColor.borderSubtle,
                glowColor: .clear
            )
        case .success:
            return StatusVisualStyle(
                accent: StatusTone.success.emphasizedColor,
                text: StatusTone.success.emphasizedColor,
                nodeBackground: StatusTone.success.color.opacity(0.11),
                nodeBorder: StatusTone.success.color.opacity(0.26),
                glowColor: StatusTone.success.color.opacity(0.15)
            )
        case .error:
            return StatusVisualStyle(
                accent: StatusTone.failure.emphasizedColor,
                text: StatusTone.failure.emphasizedColor,
                nodeBackground: StatusTone.failure.color.opacity(0.14),
                nodeBorder: StatusTone.failure.color.opacity(0.36),
                glowColor: StatusTone.failure.color.opacity(0.15)
            )
        }
    }

    static func accentStatusStyle(for status: ToolCallExecutionStatus) -> StatusVisualStyle {
        switch status {
        case .running:
            return StatusVisualStyle(
                accent: Color.accentColor.opacity(0.7),
                text: .secondary,
                nodeBackground: Color.accentColor.opacity(0.08),
                nodeBorder: Color.accentColor.opacity(0.2),
                glowColor: Color.accentColor.opacity(0.25)
            )
        case .success, .error:
            return terminalStatusStyle(for: status)
        }
    }

    static func neutralStatusStyle() -> StatusVisualStyle {
        StatusVisualStyle(
            accent: Color.secondary.opacity(0.85),
            text: Color.secondary.opacity(0.85),
            nodeBackground: JinSemanticColor.subtleSurface,
            nodeBorder: JinSemanticColor.borderSubtle,
            glowColor: .clear
        )
    }
}
