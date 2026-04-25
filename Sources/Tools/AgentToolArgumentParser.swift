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
            if let value = args[key] as? Double { return Int(value) }
            if let value = args[key] as? String, let intVal = Int(value) { return intVal }
        }
        return nil
    }
}
