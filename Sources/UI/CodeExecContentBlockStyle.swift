import SwiftUI
import AppKit

struct CodeExecContentBlockStyle {
    let iconName: String
    let iconColor: Color
    let titleColor: Color
    let badgeColor: Color
    let textColor: Color
    let headerBackground: Color
    let bodyBackground: Color
    let borderColor: Color
    let showsLineNumbers: Bool
    let usesSyntaxHighlighting: Bool

    static let code = CodeExecContentBlockStyle(
        iconName: "chevron.left.forwardslash.chevron.right",
        iconColor: .secondary.opacity(0.75),
        titleColor: .secondary,
        badgeColor: .secondary,
        textColor: .primary.opacity(0.88),
        headerBackground: JinSemanticColor.subtleSurfaceStrong,
        bodyBackground: JinSemanticColor.raisedSurface,
        borderColor: JinSemanticColor.separator.opacity(0.75),
        showsLineNumbers: true,
        usesSyntaxHighlighting: true
    )

    static let output = CodeExecContentBlockStyle(
        iconName: "terminal",
        iconColor: .secondary.opacity(0.75),
        titleColor: .secondary,
        badgeColor: .secondary,
        textColor: .secondary,
        headerBackground: JinSemanticColor.subtleSurfaceStrong,
        bodyBackground: JinSemanticColor.raisedSurface,
        borderColor: JinSemanticColor.separator.opacity(0.75),
        showsLineNumbers: false,
        usesSyntaxHighlighting: false
    )

    static let error = CodeExecContentBlockStyle(
        iconName: "exclamationmark.triangle.fill",
        iconColor: Color(nsColor: .systemOrange).opacity(0.9),
        titleColor: Color(nsColor: .systemOrange).opacity(0.95),
        badgeColor: Color(nsColor: .systemOrange).opacity(0.95),
        textColor: Color(nsColor: .systemOrange).opacity(0.95),
        headerBackground: Color(nsColor: .systemOrange).opacity(0.1),
        bodyBackground: Color(nsColor: .systemOrange).opacity(0.045),
        borderColor: Color(nsColor: .systemOrange).opacity(0.24),
        showsLineNumbers: false,
        usesSyntaxHighlighting: false
    )
}
