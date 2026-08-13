import SwiftUI

/// Stacked Token ID / Token Secret fields for Modal.
///
/// Uses a label-above-field layout and `wk-…` / `ws-…` prompts so the row title
/// is not repeated inside the secure field (the generic side-by-side chrome
/// rendered “Token ID  Token ID  •••••”).
struct ModalProxyTokenFields: View {
    @Binding var storedCredential: String
    @Binding var isIDRevealed: Bool
    @Binding var isSecretRevealed: Bool

    var body: some View {
        JinFormFieldRow("Token ID") {
            JinRevealableSecureField(
                title: "wk-…",
                text: ProviderFormSupport.proxyTokenIDBinding($storedCredential),
                isRevealed: $isIDRevealed,
                usesMonospacedFont: true,
                revealHelp: "Show token ID",
                concealHelp: "Hide token ID"
            )
        }

        JinFormFieldRow("Token Secret") {
            JinRevealableSecureField(
                title: "ws-…",
                text: ProviderFormSupport.proxyTokenSecretBinding($storedCredential),
                isRevealed: $isSecretRevealed,
                usesMonospacedFont: true,
                revealHelp: "Show token secret",
                concealHelp: "Hide token secret"
            )
        }
    }
}
