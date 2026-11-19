import Foundation

enum OpenAIModelSupport {
    static func isGPT62(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case "gpt-6.2-astra", "gpt-6.2-sol":
            return true
        default:
            return false
        }
    }
}
