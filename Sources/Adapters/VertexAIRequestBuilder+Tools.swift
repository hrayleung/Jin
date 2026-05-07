import Foundation

extension VertexAIRequestBuilder {
    func makeTools(
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition]
    ) -> [[String: Any]] {
        let supportsWebSearch = modelSupport.supportsWebSearch(providerConfig: providerConfig, modelID: modelID)
        let supportsCodeExecution = modelSupport.supportsCodeExecution(modelID)
        let supportsFunctionCalling = modelSupport.supportsFunctionCalling(modelID)
        var toolArray: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch {
            toolArray.append(["googleSearch": [:]])
        }
        if controls.codeExecution?.enabled == true, supportsCodeExecution {
            toolArray.append(["codeExecution": [:]])
        }
        if let googleMapsTool = makeGoogleMapsTool(modelID: modelID, controls: controls) {
            toolArray.append(googleMapsTool)
        }
        if supportsFunctionCalling,
           !tools.isEmpty,
           let functionDeclarations = Self.translateTools(tools) as? [[String: Any]] {
            toolArray.append(["functionDeclarations": functionDeclarations])
        }

        return toolArray
    }

    func makeGoogleMapsTool(
        modelID: String,
        controls: GenerationControls
    ) -> [String: Any]? {
        guard controls.googleMaps?.enabled == true,
              modelSupport.supportsGoogleMaps(modelID) else {
            return nil
        }

        var mapsConfig: [String: Any] = [:]
        if controls.googleMaps?.enableWidget == true {
            mapsConfig["enableWidget"] = true
        }
        return ["googleMaps": mapsConfig]
    }

    func makeToolConfig(modelID: String, controls: GenerationControls) -> [String: Any]? {
        guard controls.googleMaps?.enabled == true,
              modelSupport.supportsGoogleMaps(modelID) else {
            return nil
        }

        var retrievalConfig: [String: Any] = [:]
        if let lat = controls.googleMaps?.latitude,
           let lng = controls.googleMaps?.longitude {
            retrievalConfig["latLng"] = ["latitude": lat, "longitude": lng]
        }
        if let languageCode = normalizedTrimmedString(controls.googleMaps?.languageCode) {
            retrievalConfig["languageCode"] = languageCode
        }
        guard !retrievalConfig.isEmpty else { return nil }
        return ["retrievalConfig": retrievalConfig]
    }

    static func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": tool.parameters.type,
                    "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                    "required": tool.parameters.required
                ]
            ]
        }
    }
}
