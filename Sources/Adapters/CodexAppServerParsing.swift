import Foundation

// MARK: - General Codex App Server Parsing Utilities

extension CodexAppServerAdapter {
    nonisolated static func firstPositiveInt(
        from object: [String: JSONValue],
        candidatePaths: [[String]]
    ) -> Int? {
        for path in candidatePaths {
            if let value = object.int(at: path), value > 0 {
                return value
            }
        }
        return nil
    }

    nonisolated static func trimmedValue(_ raw: String?) -> String? {
        raw?.trimmedNonEmpty
    }

    nonisolated static func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            return n
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { jsonValueToAny($0) }
        case .object(let obj):
            return obj.mapValues { jsonValueToAny($0) }
        }
    }
}
