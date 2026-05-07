import SwiftUI
import SwiftData

struct ProviderConfigFormView: View {
    @Bindable var provider: ProviderConfigEntity
    @Environment(\.modelContext) var modelContext
    @Environment(\.openURL) var openURL
    @ObservedObject var codexServerController = CodexAppServerController.shared
    @State var apiKey = ""
    @State var serviceAccountJSON = ""
    @State var codexAuthMode: CodexAuthMode = .apiKey
    @State var codexAuthStatus: CodexAuthStatus = .idle
    @State var codexAccount: CodexAppServerAdapter.AccountStatus?
    @State var codexRateLimit: CodexAppServerAdapter.RateLimitStatus?
    @State var codexPendingLoginID: String?
    @State var codexAuthTask: Task<Void, Never>?
    @State var codexServerLaunchError: String?
    @State var codexWorkingDirectoryPresets: [CodexWorkingDirectoryPreset] = []
    @State var codexWorkingDirectoryPresetsDraft: [CodexWorkingDirectoryPreset] = []
    @State var showingCodexWorkingDirectoryPresetsSheet = false
    @State var showingAPIKey = false
    @State var hasLoadedCredentials = false
    @State var credentialSaveError: String?
    @State var credentialSaveTask: Task<Void, Never>?
    @State var testStatus: TestStatus = .idle
    @State var isFetchingModels = false
    @State var modelsError: String?
    @State var showingAddModel = false
    @State var showingDeleteAllModelsConfirmation = false
    @State var showingDeleteModelConfirmation = false
    @State var showingKeepFullySupportedModelsConfirmation = false
    @State var showingKeepEnabledModelsConfirmation = false
    @State var fetchedModelsForSelection: FetchedModelsSelectionState?
    @State var modelSearchText = ""
    @State var editingModel: ModelInfo?
    @State var modelPendingDeletion: ModelInfo?
    @State var hoveredModelID: String?
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

    enum CodexAuthMode: String, CaseIterable {
        case apiKey
        case chatGPT
        case localCodex
    }

    enum CodexAuthStatus: Equatable {
        case idle
        case working
        case connected
        case failure(String)
    }
}
