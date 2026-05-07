import Foundation

/// Persistence errors
enum PersistenceError: Error, LocalizedError {
    case invalidRole(String)
    case invalidProviderType(String)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidRole(let role):
            return "Invalid message role: \(role)"
        case .invalidProviderType(let type):
            return "Invalid provider type: \(type)"
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        }
    }
}
