import SwiftUI

struct AnthropicWebSearchSheetView: View {
    @Binding var domainMode: AnthropicDomainFilterMode
    @Binding var allowedDomainsDraft: String
    @Binding var blockedDomainsDraft: String
    @Binding var locationDraft: WebSearchUserLocation
    @Binding var draftError: String?

    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        JinSheet("Web Search") {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    AnthropicWebSearchDomainFilteringCard(
                        domainMode: $domainMode,
                        allowedDomainsDraft: $allowedDomainsDraft,
                        blockedDomainsDraft: $blockedDomainsDraft,
                        draftError: $draftError
                    )
                    AnthropicWebSearchUserLocationCard(locationDraft: $locationDraft)
                    AnthropicWebSearchFooterMessage(draftError: draftError)
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.pageBackdrop
                    .ignoresSafeArea()
            }
        } actions: {
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Save") { onSave() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 400, idealHeight: 480)
    }
}
