import Foundation

extension ProviderConfigEntity {
    var allModels: [ModelInfo] {
        (try? JSONDecoder().decode([ModelInfo].self, from: modelsData)) ?? []
    }

    var enabledModels: [ModelInfo] {
        allModels.filter(\.isEnabled)
    }
}
