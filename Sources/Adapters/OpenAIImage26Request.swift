import Alamofire
import Foundation

extension OpenAIAdapter {
    func imageGenerationInputs(messages: [Message], modelID: String, controls: GenerationControls) throws -> [ImageContent] {
        guard OpenAIImageModelSupport.profile(for: modelID)?.family == .gptImage26 else {
            return inputImagesForImageGeneration(from: messages)
        }
        let options = controls.openaiImageGeneration
        let attached = messages.last(where: { $0.role == .user })?.content.compactMap { part -> ImageContent? in
            guard case .image(let image) = part else { return nil }
            return image
        } ?? []
        if options?.editGuidance != nil {
            guard attached.count >= 2 else {
                throw LLMError.invalidRequest(message: "Attach the original image first and a transparent PNG guide last for this edit.")
            }
            return attached
        }
        if options?.inputMode == .generate || options?.outputFormat?.isGenerationOnly == true {
            guard attached.isEmpty else {
                throw LLMError.invalidRequest(message: "New-image generation uses a text prompt. Remove attached images, or choose Edit Images with PNG, JPEG or WebP output.")
            }
            return []
        }
        return inputImagesForImageGeneration(from: messages)
    }

    func buildImage26Request(
        modelID: String,
        prompt: String,
        inputImages: [ImageContent],
        controls: GenerationControls
    ) throws -> URLRequest {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 32_000 else {
            throw LLMError.invalidRequest(message: "Image prompts must contain between 1 and 32,000 characters.")
        }
        var options = controls.openaiImageGeneration ?? OpenAIImageGenerationControls()
        if let size = options.size,
           let error = OpenAIImageModelSupport.validate(size: size, for: modelID, outputFormat: options.outputFormat) {
            throw LLMError.invalidRequest(message: error)
        }
        OpenAIImageModelSupport.normalize(&options, for: modelID)
        var references = inputImages
        var guide: ImageContent?
        if options.editGuidance != nil {
            guard references.count >= 2 else {
                throw LLMError.invalidRequest(message: "Attach an original image followed by a transparent PNG guide.")
            }
            guide = references.removeLast()
        }
        let isEditing = !references.isEmpty
        if options.inputMode == .generate, isEditing {
            throw LLMError.invalidRequest(message: "Choose Edit Images to use image attachments, or remove them to generate a new image.")
        }
        if options.inputMode == .edit, !isEditing {
            throw LLMError.invalidRequest(message: "Attach an image to edit, or generate an image first.")
        }
        if isEditing, options.outputFormat?.isGenerationOnly == true {
            throw LLMError.invalidRequest(message: "SVG and GIF are available for new images only. Choose PNG, JPEG or WebP for an edit.")
        }
        guard references.count <= 16 else {
            throw LLMError.invalidRequest(message: "Image editing supports at most 16 reference images, plus one markup or mask PNG.")
        }
        var fields: [String: Any] = ["model": modelID, "prompt": prompt]
        if let count = options.count { fields["n"] = min(max(count, 1), 10) }
        if let size = options.size { fields["size"] = size.rawValue }
        if let quality = options.quality { fields["quality"] = quality.rawValue }
        if let complexity = options.complexity { fields["complexity"] = complexity.rawValue }
        if let background = options.background { fields["background"] = background.rawValue }
        if let format = options.outputFormat { fields["output_format"] = format.rawValue }
        if let compression = options.outputCompression { fields["output_compression"] = min(max(compression, 0), 100) }
        if let moderation = options.moderation { fields["moderation"] = moderation.rawValue }
        if let user = options.user?.trimmedNonEmpty { fields["user"] = user }
        if let count = options.frameCount { fields["frame_count"] = count }
        if let duration = options.frameDurationMilliseconds { fields["frame_duration_ms"] = duration }

        // Typed image settings own these fields. Inherited provider-specific values
        // must not override validation or change model/transport/output MIME type.
        let reserved: Set<String> = [
            "model", "prompt", "n", "size", "quality", "complexity", "background", "output_format",
            "output_compression", "moderation", "user", "frame_count", "frame_duration_ms",
            "input_fidelity", "style", "response_format", "stream", "partial_images", "image", "image[]",
            "images", "markup", "mask"
        ]
        for (key, value) in controls.providerSpecific where !reserved.contains(key.lowercased()) {
            if key == "prompt_rewriter", guide != nil || options.outputFormat?.isGenerationOnly == true { continue }
            fields[key] = value.value
        }
        guard isEditing else {
            return try makeAuthorizedJSONRequest(url: validatedURL("\(baseURL)/images/generations"),
                apiKey: apiKey, body: fields, accept: nil, includeUserAgent: false)
        }

        // Validate local raster bytes. Remote HTTPS references go directly to OpenAI
        // in JSON; Jin never fetches arbitrary URLs to assemble multipart requests.
        let uploads = try references.enumerated().map { index, image in
            try image26Upload(image, index: index)
        }
        let guideUpload = try guide.map { try image26Upload($0, index: references.count) }
        if let guideUpload, guideUpload.mimeType.lowercased() != "image/png" {
            throw LLMError.invalidRequest(message: "The markup or mask guide must be a transparent PNG.")
        }
        if let guideData = guideUpload?.data, let kind = options.editGuidance {
            try OpenAIImageEditValidation.validateGuide(guideData, original: uploads.first?.data, kind: kind)
        }
        if uploads.contains(where: { $0.data == nil }) || (guide != nil && guideUpload?.data == nil) {
            fields["images"] = try zip(references, uploads).map { image, upload in
                ["image_url": try image26ReferenceURL(image, upload: upload)]
            }
            if let guide, let guideUpload, let kind = options.editGuidance {
                fields[kind.rawValue] = ["image_url": try image26ReferenceURL(guide, upload: guideUpload)]
            }
            return try makeAuthorizedJSONRequest(url: validatedURL("\(baseURL)/images/edits"),
                apiKey: apiKey, body: fields, accept: nil, includeUserAgent: false)
        }
        return try NetworkRequestFactory.makeMultipartRequest(
            url: validatedURL("\(baseURL)/images/edits"), headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey)
        ) { form in
            for (key, value) in fields {
                let text: String
                if let value = value as? String { text = value }
                else if let value = value as? NSNumber { text = value.stringValue }
                else if JSONSerialization.isValidJSONObject(value),
                        let data = try? JSONSerialization.data(withJSONObject: value),
                        let value = String(data: data, encoding: .utf8) { text = value }
                else { continue }
                form.append(Data(text.utf8), withName: key)
            }
            for (index, upload) in uploads.enumerated() {
                if let data = upload.data {
                    form.append(data, withName: "image[]", fileName: "reference-\(index + 1).\(upload.fileExtension)", mimeType: upload.mimeType)
                }
            }
            if let guideUpload, let data = guideUpload.data, let kind = options.editGuidance {
                form.append(data, withName: kind.rawValue, fileName: "\(kind.rawValue).png", mimeType: "image/png")
            }
        }
    }

    private struct Image26Upload {
        let data: Data?
        let mimeType: String
        var fileExtension: String { AttachmentStorageManager.fileExtension(for: mimeType) ?? "png" }
    }

    private func image26Upload(_ image: ImageContent, index: Int) throws -> Image26Upload {
        if let data = try resolvedImageData(forUpload: image) {
            let raster = try OpenAIImageEditValidation.raster(data)
            return Image26Upload(data: data, mimeType: raster.mimeType)
        }
        guard let url = image.url, url.scheme?.lowercased() == "https" else {
            throw LLMError.invalidRequest(message: "Reference image \(index + 1) is not readable. Reattach it before editing.")
        }
        guard ["image/png", "image/jpeg", "image/jpg", "image/webp"].contains(image.mimeType.lowercased()) else {
            throw LLMError.invalidRequest(message: "Image edits accept PNG, JPEG or WebP inputs.")
        }
        return Image26Upload(data: nil, mimeType: image.mimeType)
    }

    private func image26ReferenceURL(_ image: ImageContent, upload: Image26Upload) throws -> String {
        if let data = upload.data {
            let value = "data:\(upload.mimeType);base64,\(data.base64EncodedString())"
            guard value.utf8.count <= 20_971_520 else {
                throw LLMError.invalidRequest(message: "A reference is too large to combine with remote image URLs. Attach all reference files locally, or use smaller images.")
            }
            return value
        }
        return image.url!.absoluteString // Validated by image26Upload.
    }
}
