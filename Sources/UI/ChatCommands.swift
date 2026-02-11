import SwiftUI

struct ChatCommands: Commands {
    @FocusedValue(\.chatActions) private var chatActions

    var body: some Commands {
        CommandMenu("Chat") {
            Button("Focus Composer") {
                chatActions?.focusComposer()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(chatActions == nil)

            Button("Attach…") {
                chatActions?.attach()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!(chatActions?.canAttach ?? false))

            Button("Expand Composer") {
                chatActions?.toggleExpandedComposer()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(chatActions == nil)

            Divider()

            Button("Stop Generating") {
                chatActions?.stopStreaming()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!(chatActions?.canStopStreaming ?? false))
        }
    }
}
