import Foundation

enum AgentToolArgumentParser {
    static func stringArg(_ args: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func intArg(_ args: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = args[key] as? Int { return value }
            if let value = args[key] as? Double,
               value.isFinite,
               let intVal = Int(exactly: value.rounded(.towardZero)) {
                return intVal
            }
            if let value = args[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let intVal = Int(trimmed) { return intVal }
            }
        }
        return nil
    }
}
