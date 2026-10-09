import SwiftUI

struct JinSettingsStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        JinSettingsControlRow(title) {
            HStack(spacing: JinSpacing.small) {
                Text(value.formatted())
                    .monospacedDigit()
                    .frame(minWidth: 24, alignment: .trailing)
                    .accessibilityHidden(true)

                Stepper(title, value: $value, in: range)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel(title)
                    .accessibilityValue(value.formatted())
            }
            .fixedSize()
        }
    }
}
