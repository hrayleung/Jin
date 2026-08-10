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
            HStack(alignment: .center, spacing: JinSpacing.medium) {
                Text(title)

                Spacer()


                control()
                }

            if let supportingText, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
