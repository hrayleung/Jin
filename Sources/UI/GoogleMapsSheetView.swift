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
                    GoogleMapsBasicsCard(
                        isEnabled: $draft.enabled,
                        hasLiveLocation: hasLiveLocation
                    )

                    GoogleMapsLocationBiasCard(
                        latitudeDraft: $latitudeDraft,
                        longitudeDraft: $longitudeDraft,
                        onClearCoordinates: clearCoordinates
                    ) {
                        currentLocationButton
                    }

                    GoogleMapsAdvancedCard(
                        isExpanded: $advancedExpanded,
                        languageCodeDraft: $languageCodeDraft,
                        enableWidget: enableWidgetBinding,
                        providerType: providerType
                    )

                    GoogleMapsSheetFooter(
                        draftError: draftError,
                        summaryText: summaryText,
                        hasLiveLocation: hasLiveLocation,
                        isWidgetEnabled: enableWidgetBinding.wrappedValue
                    )
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
            latitudeDraft = GoogleMapsSheetSupport.formattedCoordinateValue(coordinate.latitude)
            longitudeDraft = GoogleMapsSheetSupport.formattedCoordinateValue(coordinate.longitude)
            draftError = nil
        }
        .onChange(of: locationRequester.errorMessage) { _, message in
            guard let message else { return }
            draftError = message
        }
        #endif
    }

    @ViewBuilder
    private var currentLocationButton: some View {
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
        #else
        EmptyView()
        #endif
    }

    private func clearCoordinates() {
        latitudeDraft = ""
        longitudeDraft = ""
        draftError = nil
    }

    private var hasLiveLocation: Bool {
        GoogleMapsSheetSupport.hasLiveLocation(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        )
    }

    private var summaryText: String {
        GoogleMapsSheetSupport.summaryText(
            isEnabled: draft.enabled,
            hasLiveLocation: hasLiveLocation
        )
    }

    private var trimmedLanguageCode: String? {
        GoogleMapsSheetSupport.trimmedLanguageCode(languageCodeDraft)
    }

    private var enableWidgetBinding: Binding<Bool> {
        Binding(
            get: { draft.enableWidget == true },
            set: { draft.enableWidget = $0 ? true : nil }
        )
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
        errorMessage = GoogleMapsSheetSupport.locationErrorMessage(for: error)
    }
}
#endif
