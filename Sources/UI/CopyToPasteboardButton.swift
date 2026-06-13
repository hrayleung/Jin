import SwiftUI
import AppKit

struct CopyToPasteboardButton: View {
    let text: String
    var helpText: String = "Copy"
    var copiedHelpText: String = "Copied"
    var useProminentStyle: Bool = true
    var isDisabled: Bool? = nil

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
        .disabled(isDisabled ?? !text.containsNonWhitespace)
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
        PasteboardSupport.writeString(text)

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
