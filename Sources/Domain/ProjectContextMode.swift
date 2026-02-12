import Foundation

enum ProjectContextMode: String, Codable, CaseIterable {
    case directInjection
    case rag

    var displayName: String {
        switch self {
        case .directInjection:
            return "Direct Injection"
        case .rag:
            return "RAG"
        }
    }

    var description: String {
        switch self {
        case .directInjection:
            return "All document text injected into system prompt"
        case .rag:
            return "Relevant chunks retrieved via embedding search"
        }
    }
}
