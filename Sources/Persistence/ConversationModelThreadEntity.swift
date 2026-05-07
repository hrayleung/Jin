import Foundation
import SwiftData

/// Per-conversation model thread (independent context + controls).
@Model
final class ConversationModelThreadEntity {
    @Attribute(.unique) var id: UUID
    var providerID: String
    var modelID: String
    var modelConfigData: Data
    var displayOrder: Int
    var isSelected: Bool
    var isPrimary: Bool
    var lastActivatedAt: Date
    var createdAt: Date
    var updatedAt: Date

    @Relationship var conversation: ConversationEntity?

    init(
        id: UUID = UUID(),
        providerID: String,
        modelID: String,
        modelConfigData: Data,
        displayOrder: Int = 0,
        isSelected: Bool = true,
        isPrimary: Bool = false,
        lastActivatedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.modelConfigData = modelConfigData
        self.displayOrder = displayOrder
        self.isSelected = isSelected
        self.isPrimary = isPrimary
        self.lastActivatedAt = lastActivatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
