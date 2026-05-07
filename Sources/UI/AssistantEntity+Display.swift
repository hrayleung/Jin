import Foundation

extension AssistantEntity {
    var displayName: String {
        name.trimmedNonEmpty ?? id
    }
}
