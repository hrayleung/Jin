import SwiftUI

struct JinDetailsDisclosure<Content: View>: View {
    let title: String
    let systemImage: String
    @State private var internalIsExpanded: Bool
    private let externalIsExpanded: Binding<Bool>?
    private let content: () -> Content
    private let chevronWidth: CGFloat = 12
    private let iconWidth: CGFloat = 14

    init(
        title: String = "Details",
        systemImage: String = "info.circle",
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.externalIsExpanded = nil
        _internalIsExpanded = State(initialValue: initiallyExpanded)
        self.content = content
    }

    init(
        title: String = "Details",
        systemImage: String = "info.circle",
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.externalIsExpanded = isExpanded
        _internalIsExpanded = State(initialValue: isExpanded.wrappedValue)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpandedBinding.wrappedValue.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: JinSpacing.small) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: chevronWidth, alignment: .center)

                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: iconWidth, alignment: .center)

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
            .accessibilityHint(Text(isExpanded ? "Hides additional details" : "Shows additional details"))

            if isExpanded {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, JinSpacing.small)
                .padding(.leading, chevronWidth + iconWidth + (JinSpacing.small * 2))
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(.subtle, cornerRadius: JinRadius.large)
    }

    private var isExpandedBinding: Binding<Bool> {
        externalIsExpanded ?? $internalIsExpanded
    }

    private var isExpanded: Bool {
        isExpandedBinding.wrappedValue
    }
}
