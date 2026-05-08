import Foundation

extension ZyphraAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            includeUserAgent: false
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let entries = try JSONDecoder().decode([ZyphraModelInfo].self, from: data)
        return entries.map { $0.modelInfo() }
    }
}

private struct ZyphraModelInfo: Decodable {
    let modelId: String
    let name: String?
    let contextLength: Int?
    let type: [String]?
    let mainUseCase: [String]?
    let inputModality: [String]?
    let outputModality: [String]?
    let functionCalling: Bool?

    func modelInfo() -> ModelInfo {
        if let catalogEntry = ModelCatalog.entry(for: modelId, provider: .zyphra) {
            return ModelInfo(
                id: modelId,
                name: name ?? catalogEntry.displayName,
                capabilities: catalogEntry.capabilities,
                contextWindow: contextLength ?? catalogEntry.contextWindow,
                maxOutputTokens: catalogEntry.maxOutputTokens,
                reasoningConfig: catalogEntry.reasoningConfig
            )
        }

        return ModelInfo(
            id: modelId,
            name: name ?? modelId,
            capabilities: derivedCapabilities(),
            contextWindow: contextLength ?? 128_000,
            maxOutputTokens: nil,
            reasoningConfig: nil
        )
    }

    private func derivedCapabilities() -> ModelCapability {
        // Zyphra's gateway accepts and relays OpenAI-style tool calls for every
        // model in the current catalog despite reporting `functionCalling: false`,
        // so always enable `.toolCalling` rather than trusting that field.
        var capabilities: ModelCapability = [.streaming, .toolCalling]

        let lowercaseTags = Set((type ?? []).map { $0.lowercased() })
            .union((mainUseCase ?? []).map { $0.lowercased() })

        if lowercaseTags.contains("reasoning") {
            capabilities.insert(.reasoning)
        }

        let inputs = Set((inputModality ?? []).map { $0.lowercased() })
        if inputs.contains("image") || lowercaseTags.contains("vision") {
            capabilities.insert(.vision)
        }
        if inputs.contains("audio") {
            capabilities.insert(.audio)
        }
        if inputs.contains("video") {
            capabilities.insert(.videoInput)
        }

        return capabilities
    }
}
