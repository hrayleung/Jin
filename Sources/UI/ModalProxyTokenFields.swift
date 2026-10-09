import SwiftUI

struct ModalProxyTokenFields: View {
    @Binding var storedCredential: String
    @Binding var isIDRevealed: Bool
    @Binding var isSecretRevealed: Bool

    var body: some View {
        JinSettingsSecureFieldRow(
            "Token ID", prompt: "wk-…",
            text: ProviderFormSupport.proxyTokenIDBinding($storedCredential),
            isRevealed: $isIDRevealed, usesMonospacedFont: true,
            revealHelp: "Show token ID", concealHelp: "Hide token ID"
        )
        JinSettingsSecureFieldRow(
            "Token Secret", prompt: "ws-…",
            text: ProviderFormSupport.proxyTokenSecretBinding($storedCredential),
            isRevealed: $isSecretRevealed, usesMonospacedFont: true,
            revealHelp: "Show token secret", concealHelp: "Hide token secret"
        )
    }
}
