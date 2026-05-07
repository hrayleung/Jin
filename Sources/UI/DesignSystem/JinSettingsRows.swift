import SwiftUI

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
        labelWidth: CGFloat = 156,
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
            HStack(alignment: .top, spacing: JinSpacing.medium + 2) {
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
