import SwiftUI

struct JinSettingsCard<Content: View>: View {
    let surface: JinSurfaceVariant
    let spacing: CGFloat
    let padding: CGFloat
    let cornerRadius: CGFloat
    private let content: () -> Content

    init(
        surface: JinSurfaceVariant = .raised,
        spacing: CGFloat = JinSpacing.medium,
        padding: CGFloat = JinSpacing.large,
        cornerRadius: CGFloat = JinRadius.large,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.surface = surface
        self.spacing = spacing
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(padding)
        .jinSurface(surface, cornerRadius: cornerRadius)
    }
}
