import SwiftUI

struct ShortcutRecorderCard: View {
    @Binding var binding: AppShortcutBinding?
    @Binding var validationMessage: String?
    @State private var isRecorderActive = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .fill(JinSemanticColor.subtleSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
                )

            VStack(spacing: 4) {
                Text(binding?.displayLabel ?? "None")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, JinSpacing.small)

            #if os(macOS)
            ShortcutCaptureView(
                isFirstResponder: $isRecorderActive,
                onCapture: { capturedBinding in
                    binding = capturedBinding
                    validationMessage = nil
                },
                onClear: {
                    binding = nil
                    validationMessage = nil
                },
                onValidationError: { message in
                    validationMessage = message
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
        .frame(height: 88)
        .onTapGesture {
            isRecorderActive = true
        }
    }
}
