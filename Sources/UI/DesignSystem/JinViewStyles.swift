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
        case .outlined:
            return JinSemanticColor.separator.opacity(0.7)
        default:
            return JinSemanticColor.separator.opacity(0.7)
        }
    }

    fileprivate var lineWidth: CGFloat {
        switch self {
        case .selected:
            return JinStrokeWidth.regular
        case .neutral, .accent, .tool:
            return 0
        case .outlined:
            return JinStrokeWidth.hairline
        default:
            return JinStrokeWidth.hairline
        }
    }
}

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

struct JinFormFieldRow<Control: View>: View {
    let title: String
    let supportingText: String?
    let controlAlignment: Alignment
    private let control: () -> Control

    init(
        _ title: String,
        supportingText: String? = nil,
        controlAlignment: Alignment = .leading,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.supportingText = supportingText
        self.controlAlignment = controlAlignment
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            control()
                .frame(maxWidth: .infinity, alignment: controlAlignment)

            if let supportingText, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct JinSettingsControlRow<Control: View>: View {
    let title: String
    let supportingText: String?
    let labelWidth: CGFloat
    let controlAlignment: Alignment
    private let control: () -> Control

    init(
        _ title: String,
        supportingText: String? = nil,
        labelWidth: CGFloat = 168,
        controlAlignment: Alignment = .leading,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.supportingText = supportingText
        self.labelWidth = labelWidth
        self.controlAlignment = controlAlignment
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            HStack(alignment: .top, spacing: JinSpacing.large) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: labelWidth, alignment: .leading)
                    .padding(.top, 6)

                control()
                    .frame(maxWidth: .infinity, alignment: controlAlignment)
            }

            if let supportingText, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, labelWidth + JinSpacing.large)
            }
        }
    }
}

struct JinSettingsBlockRow<Control: View>: View {
    let title: String
    let supportingText: String?
    let controlAlignment: Alignment
    private let control: () -> Control

    init(
        _ title: String,
        supportingText: String? = nil,
        controlAlignment: Alignment = .leading,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.supportingText = supportingText
        self.controlAlignment = controlAlignment
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if let supportingText, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            control()
                .frame(maxWidth: .infinity, alignment: controlAlignment)
        }
    }
}

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
                .padding(JinSpacing.large)
                .jinSurface(.outlined, cornerRadius: JinRadius.large)

            case .plain:
                VStack(alignment: .leading, spacing: contentSpacing) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct JinRevealableSecureField: View {
    let title: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    var usesMonospacedFont: Bool = false
    var revealHelp: String = "Show value"
    var concealHelp: String = "Hide value"

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                        .textContentType(.password)
                } else {
                    SecureField(title, text: $text)
                        .textContentType(.password)
                }
            }
            .font(usesMonospacedFont ? .system(.body, design: .monospaced) : .body)
            .textFieldStyle(.roundedBorder)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(JinIconButtonStyle(showBackground: true))
            .accessibilityLabel(Text(isRevealed ? concealHelp : revealHelp))
            .accessibilityValue(Text(isRevealed ? "Visible" : "Hidden"))
            .help(isRevealed ? concealHelp : revealHelp)
            .disabled(!isRevealed && text.isEmpty)
        }
    }
}

struct JinSettingsStatusText: View {
    let text: String
    var isError: Bool = false

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func jinSurface(_ variant: JinSurfaceVariant, cornerRadius: CGFloat = JinRadius.medium) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(variant.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(variant.stroke, lineWidth: variant.lineWidth)
            )
    }

    func jinTagStyle(foreground: Color = .secondary) -> some View {
        self
            .font(.caption2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.8), lineWidth: JinStrokeWidth.hairline)
            )
    }

    func jinInfoCallout() -> some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
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
        self
            .scrollContentBackground(.hidden)
            .padding(JinSpacing.small)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(JinSemanticColor.textSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
            )
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
}
