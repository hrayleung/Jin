import SwiftUI

struct DeepSeekOCRPluginSettingsView: View {
    var body: some View {
        PluginAPIKeySettingsView(
            title: "DeepSeek OCR",
            preferenceKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey,
            testConnection: { apiKey in
                let client = DeepInfraDeepSeekOCRClient(apiKey: apiKey)
                try await client.validateAPIKey()
            }
        )
    }
}
