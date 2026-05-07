import Foundation

enum AgentToolArgumentParser {
    static func rawArguments(_ arguments: [String: AnyCodable]) -> [String: Any] {
        arguments.mapValues { $0.value }
    }

    static func rawStringArg(_ args: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                return value
            }
        }
        return nil
    }

    static func stringArg(_ args: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                if let trimmed = value.trimmedNonEmpty { return trimmed }
            }
        }
        return nil
    }

    static func normalizedStringArg(_ args: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = normalizedStringValue(args[key]) {
                return value
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
            if let value = (args[key] as? String)?.trimmedNonEmpty {
                if let intVal = Int(value) { return intVal }
            }
        }
        return nil
    }

    private static func normalizedStringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmedNonEmpty
        case let int as Int:
            return String(int)
        case let double as Double where double.isFinite:
            guard let intValue = Int(exactly: double.rounded(.towardZero)) else { return nil }
            return String(intValue)
        default:
            return nil
        }
    }
}
