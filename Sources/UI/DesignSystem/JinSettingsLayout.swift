import SwiftUI

/// How text/secure fields should sit inside a settings surface.
///
/// A grouped settings row is the field: `.plain` draws no second box, the
/// same way System Settings does. Aqua `.roundedBorder` punches a near-black
/// hole in dark mode, so the bordered case is a quiet system-fill well for
/// fields that are not already a row (environment keys, tokens).
enum JinSettingsFieldChrome: Equatable {
    case roundedBorder
    case plain
}

private struct JinSettingsFieldChromeKey: EnvironmentKey {
    static let defaultValue = JinSettingsFieldChrome.roundedBorder
}

private struct JinSettingsEnabledBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var jinSettingsEnabledBinding: Binding<Bool>? {
        get { self[JinSettingsEnabledBindingKey.self] }
        set { self[JinSettingsEnabledBindingKey.self] = newValue }
    }

    var jinSettingsFieldChrome: JinSettingsFieldChrome {
        get { self[JinSettingsFieldChromeKey.self] }
        set { self[JinSettingsFieldChromeKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func jinSettingsTextFieldStyle(_ chrome: JinSettingsFieldChrome) -> some View {
        switch chrome {
        case .plain:
            textFieldStyle(.plain)
        case .roundedBorder:
            textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(JinSemanticColor.controlFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
                }
        }
    }
}

struct JinSettingsPage<Content: View>: View {
    @Environment(\.jinSettingsEnabledBinding) private var enabledBinding
    let title: String?
    var maxWidth: CGFloat = 680
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 16
    private let content: () -> Content

    init(
        title: String? = nil,
        maxWidth: CGFloat = 680,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let enabledBinding {
                        Toggle("Enabled", isOn: enabledBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .fixedSize()
                            .accessibilityLabel("Enable \(title)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            Form {
                content()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .environment(\.jinSettingsFieldChrome, .plain)
            .jinSettingsLabelColumn()
        }
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JinSemanticColor.pageBackdrop)
    }
}

struct JinSettingsSection<Content: View>: View {
    let title: String
    let detail: String?
    private let content: () -> Content

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
        } footer: {
            if let detail, !detail.isEmpty {
                Text(detail)
            }
        }
        .listRowBackground(JinSemanticColor.controlGroup)
    }
}
