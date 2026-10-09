import SwiftUI

struct JinSettingsCard<Content: View>: View {
    let surface: JinSurfaceVariant
    let spacing: CGFloat
    let padding: CGFloat
    let cornerRadius: CGFloat
    private let content: () -> Content

    init(
        surface: JinSurfaceVariant = .group,
        spacing: CGFloat = JinSpacing.medium,
        padding: CGFloat = 14,
        cornerRadius: CGFloat = 10,
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .jinSurface(surface, cornerRadius: cornerRadius)
    }
}
