import SwiftUI

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
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .accessibilityLabel(Text(isRevealed ? concealHelp : revealHelp))
            .accessibilityValue(Text(isRevealed ? "Visible" : "Hidden"))
            .help(isRevealed ? concealHelp : revealHelp)
            .disabled(!isRevealed && text.isEmpty)
        }
    }
}
