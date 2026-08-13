import Foundation

enum ProviderFormSupport {
    /// Nested `List` inside a grouped `Form` must have a bounded height so
    /// AppKit virtualizes rows. A minHeight-only list expands to every model
    /// and hitches the first paint of the Providers pane.
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
