import SwiftUI

struct JinRevealableSecureField: View {
    let prompt: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    var usesMonospacedFont: Bool = false
    var revealHelp: String = "Show value"
    var concealHelp: String = "Hide value"

    init(
        prompt: String = "",
        text: Binding<String>,
        isRevealed: Binding<Bool>,
        usesMonospacedFont: Bool = false,
        revealHelp: String = "Show value",
        concealHelp: String = "Hide value"
    ) {
        self.prompt = prompt
        _text = text
        _isRevealed = isRevealed
        self.usesMonospacedFont = usesMonospacedFont
        self.revealHelp = revealHelp
        self.concealHelp = concealHelp
    }

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Group {
                if isRevealed {
                    TextField("", text: $text, prompt: promptText)
                        .textContentType(.password)
                } else {
                    SecureField("", text: $text, prompt: promptText)
                        .textContentType(.password)
                }
            }
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .font(usesMonospacedFont ? .system(.body, design: .monospaced) : .body)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)

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

    private var promptText: Text? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Text(trimmed)
    }
}
