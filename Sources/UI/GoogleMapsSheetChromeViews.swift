import SwiftUI

struct GoogleMapsBasicsCard: View {
    @Binding var isEnabled: Bool

    let hasLiveLocation: Bool

    var body: some View {
        JinSettingsFeatureToggleCard(
            toggleTitle: "Enable Google Maps grounding",
            isEnabled: $isEnabled
        ) {
            if hasLiveLocation {
                Text("Pinned")
                    .jinTagStyle()
            }
        }
    }
}

struct GoogleMapsLocationBiasCard<LocationButton: View>: View {
    @Binding var latitudeDraft: String
    @Binding var longitudeDraft: String

    let onClearCoordinates: () -> Void
    @ViewBuilder let locationButton: LocationButton

    private var clearCoordinatesDisabled: Bool {
        !GoogleMapsSheetSupport.hasCoordinateDrafts(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        )
    }

    var body: some View {
        JinSettingsCard {
            title
            coordinateRows
            actionsRow
        }
    }

    private var title: some View {
        Text("Location Bias")
            .font(.headline)
    }

    private var coordinateRows: some View {
        HStack(spacing: JinSpacing.medium) {
            latitudeRow
            longitudeRow
        }
    }

    private var latitudeRow: some View {
        JinFormFieldRow("Latitude", supportingText: "-90 to 90") {
            JinSettingsTextField("34.050481", text: $latitudeDraft, usesMonospacedFont: true)
        }
    }

    private var longitudeRow: some View {
        JinFormFieldRow("Longitude", supportingText: "-180 to 180") {
            JinSettingsTextField("-118.248526", text: $longitudeDraft, usesMonospacedFont: true)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: JinSpacing.small) {
            locationButton
            clearCoordinatesButton
        }
        .font(.caption.weight(.medium))
    }

    private var clearCoordinatesButton: some View {
        Button("Clear Coordinates") {
            onClearCoordinates()
        }
        .disabled(clearCoordinatesDisabled)
    }
}

struct GoogleMapsAdvancedCard: View {
    @Binding var isExpanded: Bool
    @Binding var languageCodeDraft: String
    @Binding var enableWidget: Bool

    let providerType: ProviderType?

    var body: some View {
        JinSettingsCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                advancedContent
            } label: {
                disclosureLabel
            }
        }
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if providerType == .vertexai {
                localeRow
            }

            widgetTokenRow
        }
        .padding(.top, JinSpacing.small)
    }

    private var localeRow: some View {
        JinFormFieldRow("Locale", supportingText: "Optional. Example: en_US") {
            JinSettingsTextField("en_US", text: $languageCodeDraft, usesMonospacedFont: true)
                .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var widgetTokenRow: some View {
        JinFormFieldRow("Widget Token", supportingText: "Experimental.") {
            Toggle("Request widget token", isOn: $enableWidget)
                .toggleStyle(.switch)
        }
    }

    private var disclosureLabel: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text("Advanced")
                .font(.headline)
            Spacer(minLength: 0)
            Text("Optional")
                .jinTagStyle()
        }
    }
}

struct GoogleMapsSheetFooter: View {
    let draftError: String?
    let summaryText: String
    let hasLiveLocation: Bool
    let isWidgetEnabled: Bool

    var body: some View {
        JinSettingsSheetFooter(draftError: draftError) {
            JinSettingsFooterText(summaryText)
            JinSettingsFooterText("Results appear in the response timeline as grounded place sources.")
            if hasLiveLocation {
                JinSettingsFooterText("Saved coordinates only bias this conversation.")
            }
            if isWidgetEnabled {
                JinSettingsFooterText("Jin requests a widget token but does not render the Google widget.")
            }
        }
    }
}
