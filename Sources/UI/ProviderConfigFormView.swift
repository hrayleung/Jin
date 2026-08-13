import SwiftUI
import SwiftData

struct ProviderConfigFormView: View {
    @Bindable var provider: ProviderConfigEntity
    @Environment(\.modelContext) var modelContext
    @Environment(\.openURL) var openURL
    @State var apiKey = ""
    @State var serviceAccountJSON = ""
    @State var showingAPIKey = false
    @State var showingTokenSecret = false
    @State var hasLoadedCredentials = false
    @State var credentialSaveError: String?
    @State var credentialSaveTask: Task<Void, Never>?
    /// Debounces SwiftData persistence for free-text configuration fields
    /// (name / base URL) so key-repeat is not interrupted by disk I/O, while
    /// in-memory entity values still update on every keystroke.
    @State var configurationSaveTask: Task<Void, Never>?
    @State var testStatus: TestStatus = .idle
    @State var isFetchingModels = false
    @State var modelsError: String?
    @State var showingAddModel = false
    @State var showingAddEndpoint = false
    @State var showingDeleteAllModelsConfirmation = false
    @State var showingDeleteModelConfirmation = false
    @State var showingKeepFullySupportedModelsConfirmation = false
    @State var showingKeepEnabledModelsConfirmation = false
    @State var fetchedModelsForSelection: FetchedModelsSelectionState?
    @State var modelSearchText = ""
    @State var editingModel: ModelInfo?
    @State var modelPendingDeletion: ModelInfo?
    @State var openRouterUsageStatus: OpenRouterUsageStatus = .idle
    @State var openRouterUsage: OpenRouterKeyUsage?
    @State var openRouterUsageTask: Task<Void, Never>?
    @State var claudeManagedRefreshTask: Task<Void, Never>?
    @State var claudeManagedAgents: [ClaudeManagedAgentDescriptor] = []
    @State var claudeManagedEnvironments: [ClaudeManagedEnvironmentDescriptor] = []
    @State var isRefreshingClaudeManagedResources = false
    @State var claudeManagedResourceError: String?
    @State var claudeManagedAgentIDDraft = ""
    @State var claudeManagedEnvironmentIDDraft = ""

    let providerManager = ProviderManager()
    let networkManager = NetworkManager()

    var providerType: ProviderType? {
        ProviderType(rawValue: provider.typeRaw)
    }

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }
}
