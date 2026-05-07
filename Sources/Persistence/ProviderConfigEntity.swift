import Foundation
import SwiftData

/// Provider config entity (SwiftData)
@Model
final class ProviderConfigEntity {
    @Attribute(.unique) var id: String
    var name: String
    var typeRaw: String // ProviderType.rawValue
    var iconID: String?
    var apiKey: String?
    var serviceAccountJSON: String?
    // Legacy: preserved for schema compatibility with older GitHub OAuth builds.
    var oauthClientID: String?
    // Legacy: no longer used (credentials are stored directly on this entity).
    var apiKeyKeychainID: String?
    var baseURL: String?
    var modelsData: Data // Codable [ModelInfo]
    var isEnabled: Bool = true

    init(
        id: String,
        name: String,
        typeRaw: String,
        iconID: String? = nil,
        apiKey: String? = nil,
        serviceAccountJSON: String? = nil,
        oauthClientID: String? = nil,
        apiKeyKeychainID: String? = nil,
        baseURL: String? = nil,
        modelsData: Data,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.iconID = iconID
        self.apiKey = apiKey
        self.serviceAccountJSON = serviceAccountJSON
        self.oauthClientID = oauthClientID
        self.apiKeyKeychainID = apiKeyKeychainID
        self.baseURL = baseURL
        self.modelsData = modelsData
        self.isEnabled = isEnabled
    }

    /// Convert to domain model
    func toDomain() throws -> ProviderConfig {
        guard let providerType = ProviderType(rawValue: typeRaw) else {
            throw PersistenceError.invalidProviderType(typeRaw)
        }

        let decoder = JSONDecoder()
        let models: [ModelInfo]
        if providerType == .claudeManagedAgents {
            models = []
        } else {
            models = try decoder.decode([ModelInfo].self, from: modelsData)
        }

        var config = ProviderConfig(
            id: id,
            name: name,
            type: providerType,
            iconID: iconID,
            authModeHint: apiKeyKeychainID,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON,
            baseURL: baseURL,
            models: models,
            isEnabled: isEnabled
        )
        if providerType == .claudeManagedAgents {
            config.normalizeClaudeManagedAgentDefaults()
        }
        return config
    }

    /// Create from domain model
    static func fromDomain(_ config: ProviderConfig) throws -> ProviderConfigEntity {
        let encoder = JSONEncoder()
        let modelsData = try encoder.encode(config.hasLocalModelCatalog ? config.models : [])

        return ProviderConfigEntity(
            id: config.id,
            name: config.name,
            typeRaw: config.type.rawValue,
            iconID: config.iconID,
            apiKey: config.apiKey,
            serviceAccountJSON: config.serviceAccountJSON,
            oauthClientID: nil,
            apiKeyKeychainID: config.authModeHint,
            baseURL: config.baseURL,
            modelsData: modelsData,
            isEnabled: config.isEnabled
        )
    }
}
