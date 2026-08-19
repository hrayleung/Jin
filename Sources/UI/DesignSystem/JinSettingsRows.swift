import SwiftUI

struct JinFormFieldRow<Control: View>: View {
    let title: String
    let supportingText: String?
    private let control: () -> Control

    init(
        _ title: String,
        supportingText: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.supportingText = supportingText
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)

            control()

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
    let controlAlignment: Alignment
    private let control: () -> Control

    /// Keeps the VoiceOver label/content association that `LabeledContent`
    /// used to provide, now that the row lays itself out (see
    /// `JinSettingsLabelColumn`).
    @Namespace private var labelPair

    init(
        _ title: String,
        supportingText: String? = nil,
        controlAlignment: Alignment = .trailing,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.supportingText = supportingText
        self.controlAlignment = controlAlignment
        self.control = control
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSettingsMetrics.labelColumnSpacing) {
            JinSettingsRowLabel(title)
                .accessibilityLabeledPair(role: .label, id: title, in: labelPair)

            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                control()
                    .frame(maxWidth: .infinity, alignment: controlAlignment)

                if let supportingText, !supportingText.isEmpty {
                    Text(supportingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabeledPair(role: .content, id: title, in: labelPair)
        }
    }
}

struct JinSettingsBlockRow<Control: View>: View {
    let title: String
    let supportingText: String?
    private let control: () -> Control

    init(
        _ title: String,
        supportingText: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.supportingText = supportingText
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)

            if let supportingText, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            control()
        }
    }
}
