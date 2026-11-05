import SwiftUI

struct OpenAIImageAnimationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var frames: String
    @State private var duration: String
    let onSave: (Int, Int) -> Void

    init(controls: OpenAIImageGenerationControls?, onSave: @escaping (Int, Int) -> Void) {
        _frames = State(initialValue: String(controls?.frameCount ?? 9))
        _duration = State(initialValue: String(controls?.frameDurationMilliseconds ?? 200))
        self.onSave = onSave
    }

    private var isValid: Bool {
        guard let frames = Int(frames), let duration = Int(duration) else { return false }
        return (2...64).contains(frames) && (20...2_000).contains(duration)
    }

    var body: some View {
        JinSheet("GIF Animation") {
            JinSettingsPage(horizontalPadding: 0, verticalPadding: 0) {
                JinSettingsSection("Playback") {
                    JinSettingsTextFieldRow("Frames", prompt: "9", text: $frames)
                    JinSettingsTextFieldRow("Milliseconds per frame", prompt: "200", text: $duration)
                    Text("Use 2–64 frames and 20–2,000 ms per frame. Duration is rounded to the nearest 10 ms. Larger images and more frames increase cost; the API enforces a combined pixel budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save") {
                guard isValid, let frames = Int(frames), let duration = Int(duration) else { return }
                onSave(frames, duration)
                dismiss()
            }
            .disabled(!isValid)
            .keyboardShortcut(.defaultAction)
        }
        .frame(width: 520, height: 340)
    }
}
