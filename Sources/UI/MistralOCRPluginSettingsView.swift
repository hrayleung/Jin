import SwiftUI

struct MistralOCRPluginSettingsView: View {
    var body: some View {
        PluginAPIKeySettingsView(
            title: "Mistral OCR",
            preferenceKey: AppPreferenceKeys.pluginMistralOCRAPIKey,
            testConnection: { apiKey in
                let client = MistralOCRClient(apiKey: apiKey)
                try await client.validateAPIKey()
            }
        )
    }
}
