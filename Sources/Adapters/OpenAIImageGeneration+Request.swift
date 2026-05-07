import Alamofire
import Foundation

extension OpenAIAdapter {
    func buildImageGenerationRequest(
        modelID: String,
        prompt: String,
        inputImages: [ImageContent],
        controls: GenerationControls
    ) async throws -> URLRequest {
        guard let profile = OpenAIImageModelSupport.profile(for: modelID) else {
            throw LLMError.invalidRequest(message: "Unsupported OpenAI image model: \(modelID)")
        }

        let isImageEdit = profile.supportsEdits && !inputImages.isEmpty

        if isImageEdit, profile.usesMultipartEdits {
            return try await buildMultipartImageEditRequest(
                modelID: modelID,
                prompt: prompt,
                inputImages: inputImages,
                controls: controls
            )
        }

        let endpoint = isImageEdit ? "images/edits" : "images/generations"
        var body = imageRequestBody(
            modelID: modelID,
            prompt: prompt,
            controls: controls,
            profile: profile,
            isImageEdit: isImageEdit
        )

        if isImageEdit {
            try appendJSONEditImages(inputImages, to: &body)
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/\(endpoint)"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
    }

    private func imageRequestBody(
        modelID: String,
        prompt: String,
        controls: GenerationControls,
        profile: OpenAIImageModelProfile,
        isImageEdit: Bool
    ) -> [String: Any] {
        let imageControls = controls.openaiImageGeneration
        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
        ]

        applySharedImageFields(
            to: &body,
            modelID: modelID,
            imageControls: imageControls,
            profile: profile,
            isImageEdit: isImageEdit
        )

        if !profile.isGPTImageModel {
            body["response_format"] = "b64_json"
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return body
    }

    private func applySharedImageFields(
        to body: inout [String: Any],
        modelID: String,
        imageControls: OpenAIImageGenerationControls?,
        profile: OpenAIImageModelProfile,
        isImageEdit: Bool
    ) {
        if let count = imageControls?.count, count > 0 {
            body["n"] = min(max(count, 1), 10)
        }

        if let size = imageControls?.size,
           OpenAIImageModelSupport.validate(size: size, for: modelID) == nil {
            body["size"] = size.rawValue
        }

        if let quality = imageControls?.quality,
           profile.qualityOptions.contains(quality) {
            body["quality"] = quality.rawValue
        }

        if profile.supportsStyle, let style = imageControls?.style {
            body["style"] = style.rawValue
        }

        if !profile.backgroundOptions.isEmpty,
           let background = imageControls?.background,
           profile.backgroundOptions.contains(background) {
            body["background"] = background.rawValue
        }

        if profile.supportsOutputFormat, let outputFormat = imageControls?.outputFormat {
            body["output_format"] = outputFormat.rawValue
        }

        if profile.supportsOutputCompression,
           let compression = imageControls?.outputCompression,
           let format = imageControls?.outputFormat,
           format == .jpeg || format == .webp {
            body["output_compression"] = min(max(compression, 0), 100)
        }

        if profile.supportsModeration, let moderation = imageControls?.moderation {
            body["moderation"] = moderation.rawValue
        }

        if isImageEdit,
           profile.supportsInputFidelity,
           let fidelity = imageControls?.inputFidelity {
            body["input_fidelity"] = fidelity.rawValue
        }

        if let user = normalizedTrimmedString(imageControls?.user) {
            body["user"] = user
        }
    }

    private func appendJSONEditImages(
        _ inputImages: [ImageContent],
        to body: inout [String: Any]
    ) throws {
        let imagePayloads = inputImages.compactMap { image -> [String: String]? in
            guard let imageURL = imageURLString(image),
                  !imageURL.isEmpty else {
                return nil
            }
            return ["image_url": imageURL]
        }

        guard !imagePayloads.isEmpty else {
            throw LLMError.invalidRequest(message: "OpenAI image editing requires at least one readable input image.")
        }

        body["images"] = Array(imagePayloads.prefix(16))
    }

    private func buildMultipartImageEditRequest(
        modelID: String,
        prompt: String,
        inputImages: [ImageContent],
        controls: GenerationControls
    ) async throws -> URLRequest {
        let imageControls = controls.openaiImageGeneration
        let preparedImages = try await preparedUploadImages(from: inputImages)

        guard !preparedImages.isEmpty else {
            throw LLMError.invalidRequest(message: "OpenAI image editing requires at least one readable input image.")
        }

        let url = try validatedURL("\(baseURL)/images/edits")
        let headers = NetworkRequestFactory.bearerHeaders(apiKey: apiKey)

        return try NetworkRequestFactory.makeMultipartRequest(
            url: url,
            headers: headers
        ) { formData in
            appendMultipartField("model", value: modelID, formData: formData)
            appendMultipartField("prompt", value: prompt, formData: formData)

            appendMultipartControls(
                imageControls,
                modelID: modelID,
                formData: formData
            )

            for image in preparedImages {
                formData.append(
                    image.data,
                    withName: "image[]",
                    fileName: image.filename,
                    mimeType: image.mimeType
                )
            }

            for (key, value) in controls.providerSpecific {
                appendMultipartField(key, value: value.value, formData: formData)
            }
        }
    }

    private func appendMultipartControls(
        _ imageControls: OpenAIImageGenerationControls?,
        modelID: String,
        formData: MultipartFormData
    ) {
        if let count = imageControls?.count, count > 0 {
            appendMultipartField("n", value: min(max(count, 1), 10), formData: formData)
        }

        if let size = imageControls?.size,
           OpenAIImageModelSupport.validate(size: size, for: modelID) == nil {
            appendMultipartField("size", value: size.rawValue, formData: formData)
        }

        if let quality = imageControls?.quality,
           OpenAIImageModelSupport.profile(for: modelID)?.qualityOptions.contains(quality) == true {
            appendMultipartField("quality", value: quality.rawValue, formData: formData)
        }

        if let background = imageControls?.background,
           OpenAIImageModelSupport.profile(for: modelID)?.backgroundOptions.contains(background) == true {
            appendMultipartField("background", value: background.rawValue, formData: formData)
        }

        if let outputFormat = imageControls?.outputFormat {
            appendMultipartField("output_format", value: outputFormat.rawValue, formData: formData)
        }

        if let compression = imageControls?.outputCompression,
           let format = imageControls?.outputFormat,
           format == .jpeg || format == .webp {
            appendMultipartField("output_compression", value: min(max(compression, 0), 100), formData: formData)
        }

        if let moderation = imageControls?.moderation {
            appendMultipartField("moderation", value: moderation.rawValue, formData: formData)
        }

        if let user = normalizedTrimmedString(imageControls?.user) {
            appendMultipartField("user", value: user, formData: formData)
        }
    }

    private func appendMultipartField(_ name: String, value: Any, formData: MultipartFormData) {
        guard let stringValue = multipartFieldString(for: value) else { return }
        formData.append(Data(stringValue.utf8), withName: name)
    }

    private func multipartFieldString(for value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let float as Float:
            return String(float)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        default:
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let jsonString = String(data: data, encoding: .utf8) else {
                return nil
            }
            return jsonString
        }
    }
}
