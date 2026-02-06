import SwiftUI
import AppKit

struct CopyToPasteboardButton: View {
    let text: String
    var helpText: String = "Copy"
    var copiedHelpText: String = "Copied"
    var useProminentStyle: Bool = true

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Group {
            if useProminentStyle {
                baseButton
                    .buttonStyle(JinIconButtonStyle())
            } else {
                baseButton
                    .buttonStyle(.plain)
            }
        }
        .help(didCopy ? copiedHelpText : helpText)
        // Avoid allocating a trimmed copy of large strings just to check emptiness.
        .disabled(text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) == nil)
    }

    private var baseButton: some View {
        Button {
            copyToPasteboard()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }

    @MainActor
    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) {
            didCopy = true
        }

        resetTask?.cancel()
        resetTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }

            withAnimation(.easeInOut(duration: 0.15)) {
                didCopy = false
            }
        }
    }
}
