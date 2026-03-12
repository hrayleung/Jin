import Foundation

/// Controls for provider-native code execution tools.
struct CodeExecutionControls: Codable {
    var enabled: Bool

    /// OpenAI-specific code interpreter settings.
    var openAI: OpenAICodeExecutionOptions?

    /// Anthropic-specific code execution settings.
    var anthropic: AnthropicCodeExecutionOptions?

    /// Legacy alias for the older OpenAI container-only storage shape.
    var container: CodeExecutionContainer? {
        get { openAI?.container }
        set {
            let normalized = newValue?.normalized()
            guard normalized != nil || openAI != nil else { return }

            var updated = openAI ?? OpenAICodeExecutionOptions()
            updated.container = normalized
            openAI = updated.normalized()
        }
    }

    init(
        enabled: Bool = false,
        container: CodeExecutionContainer? = nil,
        openAI: OpenAICodeExecutionOptions? = nil,
        anthropic: AnthropicCodeExecutionOptions? = nil
    ) {
        self.enabled = enabled

        if let openAI {
            self.openAI = openAI.normalized()
        } else if let container = container?.normalized() {
            self.openAI = OpenAICodeExecutionOptions(container: container)
        } else {
            self.openAI = nil
        }

        self.anthropic = anthropic?.normalized()
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case container
        case openAI
        case anthropic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false

        let legacyContainer = try container.decodeIfPresent(CodeExecutionContainer.self, forKey: .container)?.normalized()
        let decodedOpenAI = try container.decodeIfPresent(OpenAICodeExecutionOptions.self, forKey: .openAI)?.normalized()

        if var decodedOpenAI {
            if decodedOpenAI.container == nil, let legacyContainer {
                decodedOpenAI.container = legacyContainer
            }
            openAI = decodedOpenAI.normalized()
        } else if let legacyContainer {
            openAI = OpenAICodeExecutionOptions(container: legacyContainer)
        } else {
            openAI = nil
        }

        anthropic = try container.decodeIfPresent(AnthropicCodeExecutionOptions.self, forKey: .anthropic)?.normalized()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)

        let normalizedOpenAI = openAI?.normalized()
        try container.encodeIfPresent(normalizedOpenAI, forKey: .openAI)
        try container.encodeIfPresent(normalizedOpenAI?.container, forKey: .container)
        try container.encodeIfPresent(anthropic?.normalized(), forKey: .anthropic)
    }
}

/// OpenAI-specific code execution settings.
struct OpenAICodeExecutionOptions: Codable {
    /// Auto-created container configuration for the tool call.
    var container: CodeExecutionContainer?
    /// Reuse an existing container instead of creating an auto container.
    var existingContainerID: String?

    init(container: CodeExecutionContainer? = nil, existingContainerID: String? = nil) {
        self.container = container
        self.existingContainerID = existingContainerID
    }

    var isEmpty: Bool {
        container?.isEmpty != false && normalizedExistingContainerID == nil
    }

    var normalizedExistingContainerID: String? {
        Self.normalizedString(existingContainerID)
    }

    func normalized() -> OpenAICodeExecutionOptions? {
        let normalizedContainer = container?.normalized()
        let normalizedExistingContainerID = normalizedExistingContainerID

        if normalizedContainer == nil, normalizedExistingContainerID == nil {
            return nil
        }

        return OpenAICodeExecutionOptions(
            container: normalizedContainer,
            existingContainerID: normalizedExistingContainerID
        )
    }

    private static func normalizedString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// OpenAI auto-container configuration for code interpreter.
struct CodeExecutionContainer: Codable {
    /// Container type. When nil, the provider default is used.
    var type: String?
    /// Memory limit (e.g., "1g", "4g"). When nil, the provider default is used.
    var memoryLimit: String?
    /// Optional list of uploaded file IDs to copy into the auto-created container.
    var fileIDs: [String]?

    init(type: String? = nil, memoryLimit: String? = nil, fileIDs: [String]? = nil) {
        self.type = type
        self.memoryLimit = memoryLimit
        self.fileIDs = fileIDs
    }

    var isEmpty: Bool {
        normalizedType == nil && normalizedMemoryLimit == nil && normalizedFileIDs == nil
    }

    var normalizedType: String? {
        Self.normalizedString(type)
    }

    var normalizedMemoryLimit: String? {
        Self.normalizedString(memoryLimit)
    }

    var normalizedFileIDs: [String]? {
        let values = (fileIDs ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !values.isEmpty else { return nil }

        var deduped: [String] = []
        var seen: Set<String> = []
        for value in values where seen.insert(value).inserted {
            deduped.append(value)
        }
        return deduped
    }

    func normalized() -> CodeExecutionContainer? {
        let normalized = CodeExecutionContainer(
            type: normalizedType,
            memoryLimit: normalizedMemoryLimit,
            fileIDs: normalizedFileIDs
        )
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Anthropic-specific code execution settings.
struct AnthropicCodeExecutionOptions: Codable {
    /// Reuse an existing Anthropic code execution container.
    var containerID: String?

    init(containerID: String? = nil) {
        self.containerID = containerID
    }

    var isEmpty: Bool {
        normalizedContainerID == nil
    }

    var normalizedContainerID: String? {
        let trimmed = containerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalized() -> AnthropicCodeExecutionOptions? {
        guard let normalizedContainerID else { return nil }
        return AnthropicCodeExecutionOptions(containerID: normalizedContainerID)
    }
}
