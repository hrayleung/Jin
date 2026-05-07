import SwiftUI

struct AnthropicWebSearchDomainFilteringCard: View {
    @Binding var domainMode: AnthropicDomainFilterMode
    @Binding var allowedDomainsDraft: String
    @Binding var blockedDomainsDraft: String
    @Binding var draftError: String?

    var body: some View {
        JinSettingsCard {
            title
            modeRow
            domainsRow
        }
        .onChange(of: allowedDomainsDraft) { _, _ in clearDraftError() }
        .onChange(of: blockedDomainsDraft) { _, _ in clearDraftError() }
        .onChange(of: domainMode) { _, _ in clearDraftError() }
    }

    private var title: some View {
        Text("Domain Filtering")
            .font(.headline)
    }

    private var modeRow: some View {
        JinFormFieldRow("Mode") {
            JinSettingsSegmentedPicker("Mode", selection: $domainMode) {
                Text("None").tag(AnthropicDomainFilterMode.none)
                Text("Allowed only").tag(AnthropicDomainFilterMode.allowed)
                Text("Blocked").tag(AnthropicDomainFilterMode.blocked)
            }
        }
    }

    @ViewBuilder
    private var domainsRow: some View {
        if domainMode != .none {
            JinFormFieldRow(
                domainsRowTitle,
                supportingText: "One domain per line."
            ) {
                JinSettingsTextEditor(text: currentDomainsDraft, minHeight: 72)
            }
        }
    }

    private var domainsRowTitle: String {
        domainMode == .allowed ? "Allowed domains" : "Blocked domains"
    }

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

    private func clearDraftError() {
        draftError = nil
    }
}

struct AnthropicWebSearchUserLocationCard: View {
    @Binding var locationDraft: WebSearchUserLocation

    var body: some View {
        JinSettingsCard {
            title
            cityRegionRow
            countryTimezoneRow
        }
    }

    private var title: some View {
        Text("User Location")
            .font(.headline)
    }

    private var cityRegionRow: some View {
        HStack(spacing: JinSpacing.medium) {
            cityFieldRow
            regionFieldRow
        }
    }

    private var countryTimezoneRow: some View {
        HStack(spacing: JinSpacing.medium) {
            countryFieldRow
            timezoneFieldRow
        }
    }

    private var cityFieldRow: some View {
        JinFormFieldRow("City") {
            JinSettingsTextField("San Francisco", text: cityBinding)
        }
    }

    private var regionFieldRow: some View {
        JinFormFieldRow("Region") {
            JinSettingsTextField("California", text: regionBinding)
        }
    }

    private var countryFieldRow: some View {
        JinFormFieldRow("Country", supportingText: "2-letter code") {
            JinSettingsTextField("US", text: countryBinding)
                .frame(maxWidth: 120)
        }
    }

    private var timezoneFieldRow: some View {
        JinFormFieldRow("Timezone") {
            JinSettingsTextField("America/Los_Angeles", text: timezoneBinding)
        }
    }

    private var cityBinding: Binding<String> {
        Binding(
            get: { locationDraft.city ?? "" },
            set: { locationDraft.city = $0.isEmpty ? nil : $0 }
        )
    }

    private var regionBinding: Binding<String> {
        Binding(
            get: { locationDraft.region ?? "" },
            set: { locationDraft.region = $0.isEmpty ? nil : $0 }
        )
    }

    private var countryBinding: Binding<String> {
        Binding(
            get: { locationDraft.country ?? "" },
            set: { value in
                let trimmed = String(value.prefix(2)).uppercased()
                locationDraft.country = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var timezoneBinding: Binding<String> {
        Binding(
            get: { locationDraft.timezone ?? "" },
            set: { locationDraft.timezone = $0.isEmpty ? nil : $0 }
        )
    }
}

struct AnthropicWebSearchFooterMessage: View {
    let draftError: String?

    var body: some View {
        JinSettingsSheetFooter(draftError: draftError, showsDetailsWhenError: false) {
            JinSettingsFooterText("User location biases result ranking toward the specified area.")
            JinSettingsFooterText("It does not inject location context into the conversation.")
        }
    }
}
