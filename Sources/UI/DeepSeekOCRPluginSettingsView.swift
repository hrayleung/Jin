import SwiftUI

struct DeepSeekOCRPluginSettingsView: View {
    var body: some View {
        PluginAPIKeySettingsView(
            title: "DeepSeek OCR (DeepInfra)",
            preferenceKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey,
            apiKeyHint: "Uses your DeepInfra API key.",
            testConnection: { apiKey in
                let client = DeepInfraDeepSeekOCRClient(apiKey: apiKey)
                try await client.validateAPIKey()
            }
        )
    }
}
