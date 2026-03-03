import Foundation

/// Optional provider-returned model catalog metadata.
/// This is informational (for example upgrade nudges or limited-availability notes),
/// and should not be treated as manual user overrides.
struct ModelCatalogMetadata: Codable, Equatable {
    var availabilityMessage: String?
    var upgradeTargetModelID: String?
    var upgradeMessage: String?

    init(
        availabilityMessage: String? = nil,
        upgradeTargetModelID: String? = nil,
        upgradeMessage: String? = nil
    ) {
        self.availabilityMessage = availabilityMessage
        self.upgradeTargetModelID = upgradeTargetModelID
        self.upgradeMessage = upgradeMessage
    }

    var isEmpty: Bool {
        availabilityMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            && upgradeTargetModelID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            && upgradeMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }
}
