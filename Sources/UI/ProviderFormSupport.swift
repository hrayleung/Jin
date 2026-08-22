import Foundation

enum ProviderFormSupport {
    /// The model rows scroll inside a bounded viewport nested in a grouped `Form`.
    /// The bound is what makes rows virtualize — letting the container size itself
    /// to every model materializes the whole catalog and hitches the first paint of
    /// the Providers pane (435 OpenRouter models: 564 ms and 888 live NSViews eager,
    /// 37 ms and 34 lazy). Keep it a transparent viewport onto the section card — do
    /// not paint a second well.
    ///
    /// The viewport must be a `ScrollView`, never a `List`: a `List` nested in a
    /// grouped `Form` builds a `ListCoreScrollView` that refuses scroll wheel events,
    /// so a bounded one strands every row past the fold. See the note in
    /// `ProviderConfigFormView+ModelList.modelsListContent`.
    static let modelListHeight: CGFloat = 300

    struct DraftValues: Equatable {
        var name: String
        var baseURL: String
        var iconID: String?
    }

    struct ModelListSummary: Equatable {
        let totalCount: Int
        let enabledCount: Int
        let fullySupportedCount: Int

        var disabledCount: Int {
            totalCount - enabledCount
        }

        var nonFullySupportedCount: Int {
            totalCount - fullySupportedCount
        }

        func canKeepFullySupportedModels(hasProviderType: Bool) -> Bool {
            hasProviderType && fullySupportedCount > 0 && nonFullySupportedCount > 0
        }

        var canKeepEnabledModels: Bool {
            enabledCount > 0 && disabledCount > 0
        }
    }
}
