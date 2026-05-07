import Foundation

enum ToolArgumentPresentationSupport {
    static func formattedJSON(
        for arguments: [String: AnyCodable],
        allowsEmpty: Bool = false
    ) -> String? {
        let raw = rawArguments(from: arguments)
        guard allowsEmpty || !raw.isEmpty else { return nil }
        return jsonString(from: raw, options: [.prettyPrinted, .sortedKeys])
    }

    static func summary(
        for arguments: [String: AnyCodable],
        preferredKeys: [String],
        maxLength: Int,
        fallsBackToJSON: Bool
    ) -> String? {
        let raw = rawArguments(from: arguments)
        guard !raw.isEmpty else { return nil }

        if let value = preferredStringValue(in: raw, preferredKeys: preferredKeys) {
            return ToolTimelineTextSupport.oneLine(value, maxLength: maxLength)
        }

        guard fallsBackToJSON,
              let json = jsonString(from: raw, options: [.sortedKeys]) else {
            return nil
        }

        return ToolTimelineTextSupport.oneLine(json, maxLength: maxLength)
    }

    private static func rawArguments(from arguments: [String: AnyCodable]) -> [String: Any] {
        arguments.mapValues { $0.value }
    }

    private static func preferredStringValue(
        in arguments: [String: Any],
        preferredKeys: [String]
    ) -> String? {
        for key in preferredKeys {
            if let value = arguments[key] as? String,
               value.trimmedNonEmpty != nil {
                return value
            }
        }

        return nil
    }

    private static func jsonString(
        from object: [String: Any],
        options: JSONSerialization.WritingOptions
    ) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
