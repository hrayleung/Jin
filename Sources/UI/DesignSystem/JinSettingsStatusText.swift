import SwiftUI

struct JinSettingsStatusText: View {
    static let connectionVerifiedMessage = "Connection verified."

    static func isConnectionVerifiedStatus(_ message: String, isError: Bool) -> Bool {
        !isError && message == connectionVerifiedMessage
    }

    let text: String
    var isError: Bool = false
    var isSuccess: Bool = false

    var body: some View {
        if isError || isSuccess {
            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.xSmall) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)

                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(statusColor)
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(statusColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(statusColor.opacity(0.25), lineWidth: JinStrokeWidth.hairline)
            )
        } else {
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusColor: Color {
        isError ? .red : .green
    }
}

struct JinSettingsErrorText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}
