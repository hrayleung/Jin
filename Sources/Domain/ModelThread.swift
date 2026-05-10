import Foundation

/// Domain representation of a per-conversation model thread.
///
/// A conversation may contain multiple parallel threads (one per model the
/// user has wired up for that chat). The persistence layer mirrors this as
/// `ConversationModelThreadEntity`; this struct is the value-type form for
/// round-tripping and tests.
struct ModelThread: Identifiable, Codable {
    let id: UUID
    var providerID: String
    var modelID: String
    var controls: GenerationControls
    var displayOrder: Int
    var isSelected: Bool
    var isPrimary: Bool

    init(
        id: UUID = UUID(),
        providerID: String,
        modelID: String,
        controls: GenerationControls = GenerationControls(),
        displayOrder: Int = 0,
        isSelected: Bool = true,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.controls = controls
        self.displayOrder = displayOrder
        self.isSelected = isSelected
        self.isPrimary = isPrimary
    }
}
