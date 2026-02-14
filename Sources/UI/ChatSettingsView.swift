import SwiftUI

struct ChatSettingsView: View {
    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false

    var body: some View {
        Form {
            Section("Send Behavior") {
                Toggle("Use \u{2318}Return to send", isOn: $sendWithCommandEnter)

                Text(sendBehaviorDescription)
                    .jinInfoCallout()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
    }

    private var sendBehaviorDescription: String {
        if sendWithCommandEnter {
            return "Press Return to insert a new line. Press \u{2318}\u{21A9} to send."
        }
        return "Press Return to send. Press Shift+Return to insert a new line."
    }
}
