import Foundation

enum AnthropicRequestPreparationSupport {
    static func betaHeader(
        from controls: GenerationControls,
        messages: [Message],
        codeExecutionEnabled: Bool
    ) -> String? {
        mergedBetaHeader(
            extractBetaHeader(from: controls),
            additions: requestUsesFilesAPI(messages, codeExecutionEnabled: codeExecutionEnabled)
                ? [anthropicFilesAPIBetaHeader]
                : []
        )
    }

    static func requestUsesFilesAPI(_ messages: [Message], codeExecutionEnabled: Bool) -> Bool {
        let allowedMIMETypes = codeExecutionEnabled
            ? anthropicHostedDocumentMIMETypes.union(anthropicCodeExecutionUploadMIMETypes)
            : anthropicHostedDocumentMIMETypes

        for message in messages {
            for part in message.content {
                guard case .file(let file) = part else { continue }
                if allowedMIMETypes.contains(normalizedMIMEType(file.mimeType)) {
                    return true
                }
            }
        }

        return false
    }

    static func providerSpecificStringArray(_ value: Any) -> [String]? {
        if let strings = value as? [String] {
            return strings
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }
        }
        return nil
    }

    static func extractBetaHeader(from controls: GenerationControls) -> String? {
        for key in ["anthropic_beta", "anthropic-beta"] {
            guard let rawValue = controls.providerSpecific[key]?.value else { continue }

            if let string = rawValue as? String, let value = string.trimmedNonEmpty {
                return value
            }

            if let values = providerSpecificStringArray(rawValue) {
                let joined = values
                    .map(\.trimmed)
                    .filter { !$0.isEmpty }
                    .joined(separator: ",")
                if !joined.isEmpty {
                    return joined
                }
            }
        }

        return nil
    }

    static func mergedBetaHeader(_ existing: String?, additions: [String]) -> String? {
        var values: [String] = []
        var seen: Set<String> = []

        func append(_ raw: String?) {
            guard let raw else { return }
            let parts = raw
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
            for part in parts where seen.insert(part).inserted {
                values.append(part)
            }
        }

        append(existing)
        for addition in additions {
            append(addition)
        }

        return values.isEmpty ? nil : values.joined(separator: ",")
    }
}
