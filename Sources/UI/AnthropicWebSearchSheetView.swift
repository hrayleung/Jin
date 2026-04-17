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
                    domainFilteringCard
                    userLocationCard
                    footerMessage
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

    // MARK: - Domain Filtering Card

    private var domainFilteringCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text("Domain Filtering")
                .font(.headline)

            JinFormFieldRow("Mode") {
                Picker("Mode", selection: $domainMode) {
                    Text("None").tag(AnthropicDomainFilterMode.none)
                    Text("Allowed only").tag(AnthropicDomainFilterMode.allowed)
                    Text("Blocked").tag(AnthropicDomainFilterMode.blocked)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if domainMode != .none {
                JinFormFieldRow(
                    domainMode == .allowed ? "Allowed domains" : "Blocked domains",
                    supportingText: "One domain per line."
                ) {
                    TextEditor(text: currentDomainsDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 72)
                        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                                .stroke(JinSemanticColor.separator, lineWidth: JinStrokeWidth.hairline)
                        )
                }
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
        .onChange(of: allowedDomainsDraft) { _, _ in draftError = nil }
        .onChange(of: blockedDomainsDraft) { _, _ in draftError = nil }
        .onChange(of: domainMode) { _, _ in draftError = nil }
    }

    // MARK: - User Location Card

    private var userLocationCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text("User Location")
                .font(.headline)

            HStack(spacing: JinSpacing.medium) {
                JinFormFieldRow("City") {
                    TextField("San Francisco", text: Binding(
                        get: { locationDraft.city ?? "" },
                        set: { locationDraft.city = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                JinFormFieldRow("Region") {
                    TextField("California", text: Binding(
                        get: { locationDraft.region ?? "" },
                        set: { locationDraft.region = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: JinSpacing.medium) {
                JinFormFieldRow("Country", supportingText: "2-letter code") {
                    TextField("US", text: Binding(
                        get: { locationDraft.country ?? "" },
                        set: { val in
                            let trimmed = String(val.prefix(2)).uppercased()
                            locationDraft.country = trimmed.isEmpty ? nil : trimmed
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                }

                JinFormFieldRow("Timezone") {
                    TextField("America/Los_Angeles", text: Binding(
                        get: { locationDraft.timezone ?? "" },
                        set: { locationDraft.timezone = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerMessage: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if let draftError {
                Text(draftError)
                    .jinInlineErrorText()
                    .padding(.horizontal, JinSpacing.small)
                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
            }

            JinDetailsDisclosure {
                Text("User location biases result ranking toward the specified area.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("It does not inject location context into the conversation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var currentDomainsDraft: Binding<String> {
        Binding(
            get: {
                switch domainMode {
                case .none:
                    return ""
                case .allowed:
                    return allowedDomainsDraft
                case .blocked:
                    return blockedDomainsDraft
                }
            },
            set: { value in
                switch domainMode {
                case .none:
                    break
                case .allowed:
                    allowedDomainsDraft = value
                case .blocked:
                    blockedDomainsDraft = value
                }
            }
        )
    }
}
