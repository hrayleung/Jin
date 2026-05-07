import SwiftUI

struct JinSettingsPage<Content: View>: View {
    var maxWidth: CGFloat = 680
    var horizontalPadding: CGFloat = 28
    var verticalPadding: CGFloat = 24
    private let content: () -> Content

    init(
        maxWidth: CGFloat = 680,
        horizontalPadding: CGFloat = 28,
        verticalPadding: CGFloat = 24,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JinSpacing.xLarge) {
                content()
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(JinSemanticColor.detailSurface)
    }
}

struct JinSettingsSection<Content: View>: View {
    enum Style {
        case card
        case plain
    }

    let title: String
    let detail: String?
    let style: Style
    let contentSpacing: CGFloat
    private let content: () -> Content

    init(
        _ title: String,
        detail: String? = nil,
        style: Style = .card,
        contentSpacing: CGFloat = JinSpacing.medium,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.style = style
        self.contentSpacing = contentSpacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text(title)
                    .font(.headline)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch style {
            case .card:
                VStack(alignment: .leading, spacing: contentSpacing) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, JinSpacing.medium)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(JinSemanticColor.separator.opacity(0.6))
                        .frame(height: JinStrokeWidth.hairline)
                }

            case .plain:
                VStack(alignment: .leading, spacing: contentSpacing) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
