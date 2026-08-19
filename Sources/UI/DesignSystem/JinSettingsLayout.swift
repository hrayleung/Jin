import SwiftUI

/// How text/secure fields should sit inside a settings surface.
///
/// Grouped `Form` already draws the section card. A second Aqua
/// `.roundedBorder` well punches a near-black hole through that card in dark
/// mode. Card-based forms (`JinSettingsCard`) have no such card, so they keep
/// the rounded well.
enum JinSettingsFieldChrome: Equatable {
    case roundedBorder
    case plain
}

private struct JinSettingsFieldChromeKey: EnvironmentKey {
    static let defaultValue = JinSettingsFieldChrome.roundedBorder
}

extension EnvironmentValues {
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
            textFieldStyle(.roundedBorder)
        }
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
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .environment(\.jinSettingsFieldChrome, .plain)
        .jinSettingsLabelColumn()
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JinSemanticColor.detailSurface)
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
        } footer: {
            if let detail, !detail.isEmpty {
                Text(detail)
            }
        }
    }
}
