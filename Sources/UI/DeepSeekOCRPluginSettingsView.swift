import SwiftUI

struct DeepSeekOCRPluginSettingsView: View {
    var body: some View {
        PluginAPIKeySettingsView(
            title: "DeepSeek OCR (DeepInfra)",
            preferenceKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey,
            apiKeyHint: "Use your DeepInfra API key here.",
            testConnection: { apiKey in
                let client = DeepInfraDeepSeekOCRClient(apiKey: apiKey)
                try await client.validateAPIKey()
            }
        )
    }
}
