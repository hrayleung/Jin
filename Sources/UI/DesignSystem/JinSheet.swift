import SwiftUI

/// A macOS sheet has one heading and a stable trailing action area. Keeping
/// actions outside the scroll view also keeps long forms usable in small windows.
struct JinSheet<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String?
    private let content: () -> Content
    private let actions: () -> Actions

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(JinSemanticColor.pageBackdrop)
        .jinSettingsLabelColumn()
        // A presented editor is not the plugin page that opened it.
        .environment(\.jinSettingsEnabledBinding, nil)
    }
}
