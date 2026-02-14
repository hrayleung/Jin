import SwiftUI

struct NetworkSettingsView: View {
    @AppStorage(AppPreferenceKeys.allowAutomaticNetworkRequests) private var allowAutomaticNetworkRequests = false

    var body: some View {
        Form {
            Section("Network") {
                Toggle("Allow automatic network requests", isOn: $allowAutomaticNetworkRequests)

                Text("When off, Jin only makes network requests from explicit actions (e.g. Send, Fetch Models, Test Connection).")
                    .jinInfoCallout()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
    }
}
