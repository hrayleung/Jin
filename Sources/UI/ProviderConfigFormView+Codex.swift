import SwiftUI

extension ProviderConfigFormView {
    var codexOverviewSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Jin talks to Codex App Server over WebSocket. Use this screen for provider-level setup, then tune per-chat sandbox, personality, and working directory from the chat toolbar.")
                .jinInfoCallout()
        }
        .padding(.vertical, 4)
    }
}
