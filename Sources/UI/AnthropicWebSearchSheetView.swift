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
        NavigationStack {
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
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Web Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 400, idealHeight: 480)
    }
}
