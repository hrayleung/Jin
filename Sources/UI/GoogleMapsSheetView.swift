import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif

struct GoogleMapsSheetView: View {
    @Binding var draft: GoogleMapsControls
    @Binding var latitudeDraft: String
    @Binding var longitudeDraft: String
    @Binding var languageCodeDraft: String
    @Binding var draftError: String?

    let providerType: ProviderType?
    let isValid: Bool

    var onCancel: () -> Void
    var onSave: () -> Bool

    @State private var advancedExpanded = false
    #if canImport(CoreLocation)
    @StateObject private var locationRequester = GoogleMapsLocationRequester()
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    summaryCard
                    basicsCard
                    locationCard
                    advancedCard
                    footerContent
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Google Maps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave() {
                            onCancel()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 540)
        .onAppear {
            if !advancedExpanded {
                advancedExpanded = draft.enableWidget == true || trimmedLanguageCode != nil
            }
        }
        .onChange(of: draft.enabled) { _, _ in
            draftError = nil
        }
        .onChange(of: latitudeDraft) { _, _ in
            draftError = nil
        }
        .onChange(of: longitudeDraft) { _, _ in
            draftError = nil
        }
        .onChange(of: languageCodeDraft) { _, _ in
            draftError = nil
        }
        #if canImport(CoreLocation)
        .onChange(of: locationRequester.coordinate) { _, coordinate in
            guard let coordinate else { return }
            latitudeDraft = Self.formattedCoordinateValue(coordinate.latitude)
            longitudeDraft = Self.formattedCoordinateValue(coordinate.longitude)
            draftError = nil
        }
        .onChange(of: locationRequester.errorMessage) { _, message in
            guard let message else { return }
            draftError = message
        }
        #endif
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            summaryRow(
                "Current mode",
                value: draft.enabled ? "Grounded" : "Off",
                foreground: draft.enabled ? .accentColor : .secondary
            )

            summaryRow(
                "Location bias",
                value: hasLiveLocation ? "Pinned" : "None"
            )

            if providerType == .vertexai,
               let locale = trimmedLanguageCode {
                summaryRow("Result locale", value: locale)
            }

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text("Basics")
                .font(.headline)

            Toggle("Enable Google Maps grounding", isOn: $draft.enabled)
                .toggleStyle(.switch)

            Text("Use Maps data for nearby places, directions, travel context, and other location-aware prompts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text("Location Bias")
                .font(.headline)

            Text("Optional. Provide coordinates to bias results around a specific area.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: JinSpacing.medium) {
                fieldRow("Latitude", hint: "Between -90 and 90.") {
                    TextField("34.050481", text: $latitudeDraft)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }

                fieldRow("Longitude", hint: "Between -180 and 180.") {
                    TextField("-118.248526", text: $longitudeDraft)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: JinSpacing.small) {
                #if canImport(CoreLocation)
                Button {
                    draftError = nil
                    locationRequester.requestLocation()
                } label: {
                    if locationRequester.isResolving {
                        Label("Locating…", systemImage: "location.magnifyingglass")
                    } else {
                        Label("Use Current Location", systemImage: "location")
                    }
                }
                .disabled(locationRequester.isResolving)
                #endif

                Button("Clear Coordinates") {
                    latitudeDraft = ""
                    longitudeDraft = ""
                    draftError = nil
                }
                .disabled(latitudeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && longitudeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.caption.weight(.medium))

            if hasLiveLocation {
                Text("Saved coordinates are only used to bias Maps grounding for this conversation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var advancedCard: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                if providerType == .vertexai {
                    fieldRow("Locale", hint: "Optional Vertex AI locale, for example en_US or ja_JP.") {
                        TextField("en_US", text: $languageCodeDraft)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                }

                fieldRow(
                    "Widget Token",
                    hint: "Experimental. Jin does not render the Google Maps widget yet; this only requests the context token."
                ) {
                    Toggle("Request widget token", isOn: enableWidgetBinding)
                        .toggleStyle(.switch)
                }
            }
            .padding(.top, JinSpacing.small)
        } label: {
            HStack(alignment: .center, spacing: JinSpacing.small) {
                Text("Advanced")
                    .font(.headline)
                Spacer(minLength: 0)
                Text("Optional")
                    .jinTagStyle()
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    @ViewBuilder
    private var footerContent: some View {
        if let draftError {
            Text(draftError)
                .jinInlineErrorText()
                .padding(.horizontal, JinSpacing.small)
                .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
        } else {
            Text("Google Maps results appear in the response timeline as grounded place sources. Enable the widget token only if you plan to embed Google's widget yourself later.")
                .jinInfoCallout()
        }
    }

    private var hasLiveLocation: Bool {
        let lat = latitudeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let lng = longitudeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !lat.isEmpty && !lng.isEmpty
    }

    private var summaryText: String {
        if draft.enabled {
            if hasLiveLocation {
                return "Maps grounding is on and will bias results using your pinned coordinates."
            }
            return "Maps grounding is on. Gemini can cite places and other Maps-backed sources when the prompt needs them."
        }
        if hasLiveLocation {
            return "A location is saved, but Maps grounding is currently off."
        }
        return "Turn Maps grounding on when you want nearby places, area summaries, and other place-aware answers."
    }

    private var trimmedLanguageCode: String? {
        let trimmed = languageCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var enableWidgetBinding: Binding<Bool> {
        Binding(
            get: { draft.enableWidget == true },
            set: { draft.enableWidget = $0 ? true : nil }
        )
    }

    private func summaryRow(_ title: String, value: String, foreground: Color = .secondary) -> some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Text(value)
                .jinTagStyle(foreground: foreground)
        }
    }

    @ViewBuilder
    private func fieldRow<Control: View>(
        _ title: String,
        hint: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func formattedCoordinateValue(_ value: Double) -> String {
        let formatted = String(format: "%.6f", value)
        return formatted.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

#if canImport(CoreLocation)
private struct GoogleMapsResolvedCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

@MainActor
private final class GoogleMapsLocationRequester: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var isResolving = false
    @Published private(set) var coordinate: GoogleMapsResolvedCoordinate?
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        coordinate = nil
        errorMessage = nil

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isResolving = true
            manager.requestLocation()
        case .notDetermined:
            isResolving = true
            manager.requestWhenInUseAuthorization()
        case .restricted:
            isResolving = false
            errorMessage = "Location access is restricted on this Mac."
        case .denied:
            isResolving = false
            errorMessage = "Location access is denied for Jin. Allow it in System Settings > Privacy & Security > Location Services."
        @unknown default:
            isResolving = false
            errorMessage = "Location access is unavailable right now."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if isResolving {
                manager.requestLocation()
            }
        case .restricted:
            isResolving = false
            errorMessage = "Location access is restricted on this Mac."
        case .denied:
            isResolving = false
            errorMessage = "Location access is denied for Jin. Allow it in System Settings > Privacy & Security > Location Services."
        case .notDetermined:
            break
        @unknown default:
            isResolving = false
            errorMessage = "Location access is unavailable right now."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isResolving = false
            errorMessage = "Current location could not be determined."
            return
        }

        coordinate = GoogleMapsResolvedCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        isResolving = false
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isResolving = false
        errorMessage = Self.userFacingMessage(for: error)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let locationError = error as? CLError {
            switch locationError.code {
            case .denied:
                return "Location access was denied."
            case .locationUnknown:
                return "Current location is temporarily unavailable. Try again in a moment."
            default:
                break
            }
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Current location could not be determined."
        }
        return message
    }
}
#endif
