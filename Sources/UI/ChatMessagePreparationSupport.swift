import Collections
import Foundation
import AppKit

enum ChatMessagePreparationSupport {

    struct ThreadPreparedUserMessage {
        let threadID: UUID
        let parts: [ContentPart]
    }

    struct MessagePreparationProfile {
        let threadID: UUID
        let modelName: String
        let supportsVideoGenerationControl: Bool
        let supportsMediaGenerationControl: Bool
        let supportsNativePDF: Bool
        let supportsVision: Bool
        let pdfProcessingMode: PDFProcessingMode
    }

    struct PreparedPDFContent {
        let extractedText: String?
        let additionalParts: [ContentPart]
    }

    static func resolvedSystemPrompt(conversationSystemPrompt: String?, assistant: AssistantEntity?) -> String? {
        let conversationPrompt = conversationSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantPrompt = assistant?.systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyLanguage = assistant?.replyLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)

        var prompt = conversationPrompt
        if prompt?.isEmpty != false {
            prompt = assistantPrompt
        }

        if let replyLanguage, !replyLanguage.isEmpty {
            if prompt?.isEmpty != false {
                prompt = "Always reply in \(replyLanguage)."
            } else {
                prompt = "\(prompt!)\n\nAlways reply in \(replyLanguage)."
            }
        }

        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func providerType(forProviderID providerID: String, providers: [ProviderConfigEntity]) -> ProviderType? {
        if let provider = providers.first(where: { $0.id == providerID }),
           let resolvedType = ProviderType(rawValue: provider.typeRaw) {
            return resolvedType
        }
        return ProviderType(rawValue: providerID)
    }

    static func supportsImageGenerationModel(providerType: ProviderType?, lowerModelID: String) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket:
            return ChatView.openAIImageGenerationModelIDs.contains(lowerModelID)
        case .xai:
            return ChatView.xAIImageGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return ChatView.geminiImageGenerationModelIDs.contains(lowerModelID)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .none:
            return false
        }
    }

    static func supportsVideoGenerationModel(providerType: ProviderType?, lowerModelID: String) -> Bool {
        switch providerType {
        case .xai:
            return ChatView.xAIVideoGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return ChatView.googleVideoGenerationModelIDs.contains(lowerModelID)
        default:
            return false
        }
    }

    static func supportsNativePDFForThread(
        providerType: ProviderType?,
        lowerModelID: String,
        supportsMediaGenerationControl: Bool,
        resolvedModelSettings: ResolvedModelSettings?
    ) -> Bool {
        guard !supportsMediaGenerationControl else { return false }
        guard let providerType else { return false }

        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .perplexity, .xai, .gemini, .vertexai:
            break
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .fireworks, .cerebras, .sambanova, .morphllm:
            return false
        }

        if resolvedModelSettings?.capabilities.contains(.nativePDF) == true {
            return true
        }

        return JinModelSupport.supportsNativePDF(providerType: providerType, modelID: lowerModelID)
    }

    static func messagePreparationProfile(
        for thread: ConversationModelThreadEntity,
        providers: [ProviderConfigEntity],
        controls: GenerationControls,
        mistralOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool,
        defaultPDFProcessingFallbackMode: PDFProcessingMode
    ) throws -> MessagePreparationProfile {
        let providerTypeSnapshot = providerType(forProviderID: thread.providerID, providers: providers)
        let providerEntity = providers.first(where: { $0.id == thread.providerID })
        let resolvedModelID = ChatModelCapabilitySupport.effectiveModelID(
            modelID: thread.modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        let lowerModelID = resolvedModelID.lowercased()
        let modelInfo = ChatModelCapabilitySupport.resolvedModelInfo(
            modelID: thread.modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        let normalizedModelInfoSnapshot = modelInfo.map {
            ChatModelCapabilitySupport.normalizedSelectedModelInfo($0, providerType: providerTypeSnapshot)
        }
        let resolvedModelSettings = normalizedModelInfoSnapshot.map {
            ModelSettingsResolver.resolve(model: $0, providerType: providerTypeSnapshot)
        }

        let supportsImageGen = (resolvedModelSettings?.capabilities.contains(.imageGeneration) == true)
            || supportsImageGenerationModel(providerType: providerTypeSnapshot, lowerModelID: lowerModelID)
        let supportsVideoGen = (resolvedModelSettings?.capabilities.contains(.videoGeneration) == true)
            || supportsVideoGenerationModel(providerType: providerTypeSnapshot, lowerModelID: lowerModelID)
        let supportsMediaGen = supportsImageGen || supportsVideoGen
        let nativePDFSupported = supportsNativePDFForThread(
            providerType: providerTypeSnapshot,
            lowerModelID: lowerModelID,
            supportsMediaGenerationControl: supportsMediaGen,
            resolvedModelSettings: resolvedModelSettings
        )
        let supportsVision = (resolvedModelSettings?.capabilities.contains(.vision) == true)
            || supportsImageGen
            || supportsVideoGen
        let threadControls: GenerationControls
        do {
            threadControls = try JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
        } catch {
            throw LLMError.decodingError(message: "Failed to load conversation settings: \(error.localizedDescription)")
        }
        let pdfMode = ChatModelCapabilitySupport.resolvedPDFProcessingMode(
            controls: threadControls,
            supportsNativePDF: nativePDFSupported,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled
        )
        let modelName = modelInfo?.name ?? resolvedModelID

        return MessagePreparationProfile(
            threadID: thread.id,
            modelName: modelName,
            supportsVideoGenerationControl: supportsVideoGen,
            supportsMediaGenerationControl: supportsMediaGen,
            supportsNativePDF: nativePDFSupported,
            supportsVision: supportsVision,
            pdfProcessingMode: pdfMode
        )
    }

    static func resolvedRemoteVideoInputURL(from raw: String, supportsExplicitRemoteVideoURLInput: Bool) throws -> URL? {
        guard supportsExplicitRemoteVideoURLInput else { return nil }
        guard !raw.isEmpty else { return nil }

        guard let url = URL(string: raw),
              !url.isFileURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LLMError.invalidRequest(message: "Video URL must be a valid http(s) link.")
        }

        return url
    }

    static func inferredVideoMIMEType(from url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "mpeg", "mpg": return "video/mpeg"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp", "3gpp": return "video/3gpp"
        default: return "video/mp4"
        }
    }

    static func buildUserMessageParts(
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: MessagePreparationProfile,
        preparedContentForPDF: (DraftAttachment, MessagePreparationProfile, PDFProcessingMode, Int, Int, MistralOCRClient?, DeepInfraDeepSeekOCRClient?) async throws -> PreparedPDFContent
    ) async throws -> [ContentPart] {
        var parts: [ContentPart] = []
        parts.reserveCapacity(attachments.count + (messageText.isEmpty ? 0 : 1) + (remoteVideoURL == nil ? 0 : 1))

        if let remoteVideoURL {
            guard profile.supportsVideoGenerationControl else {
                throw LLMError.invalidRequest(
                    message: "Remote video URL is only supported by video-capable models. (\(profile.modelName))"
                )
            }
            parts.append(
                .video(
                    VideoContent(
                        mimeType: inferredVideoMIMEType(from: remoteVideoURL),
                        data: nil,
                        url: remoteVideoURL,
                        assetDisposition: .externalReference
                    )
                )
            )
        }

        let pdfCount = attachments.filter(\.isPDF).count

        let requestedMode = profile.pdfProcessingMode
        if pdfCount > 0, requestedMode == .native, !profile.supportsNativePDF {
            throw PDFProcessingError.nativePDFNotSupported(modelName: profile.modelName)
        }

        let mistralClient: MistralOCRClient?
        if pdfCount > 0, requestedMode == .mistralOCR {
            let key = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginMistralOCRAPIKey)
            let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw PDFProcessingError.mistralAPIKeyMissing
            }

            mistralClient = MistralOCRClient(apiKey: trimmed)
        } else {
            mistralClient = nil
        }

        let deepSeekClient: DeepInfraDeepSeekOCRClient?
        if pdfCount > 0, requestedMode == .deepSeekOCR {
            let key = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
            let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw PDFProcessingError.deepInfraAPIKeyMissing
            }

            deepSeekClient = DeepInfraDeepSeekOCRClient(apiKey: trimmed)
        } else {
            deepSeekClient = nil
        }

        var pdfOrdinal = 0
        for attachment in attachments {
            try Task.checkCancellation()

            if attachment.isImage {
                parts.append(.image(ImageContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isVideo {
                parts.append(.video(VideoContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isAudio {
                parts.append(.audio(AudioContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isPDF {
                pdfOrdinal += 1
                let prepared = try await preparedContentForPDF(
                    attachment,
                    profile,
                    requestedMode,
                    pdfCount,
                    pdfOrdinal,
                    mistralClient,
                    deepSeekClient
                )

                parts.append(
                    .file(
                        FileContent(
                            mimeType: attachment.mimeType,
                            filename: attachment.filename,
                            data: nil,
                            url: attachment.fileURL,
                            extractedText: prepared.extractedText
                        )
                    )
                )
                parts.append(contentsOf: prepared.additionalParts)
                continue
            }

            parts.append(
                .file(
                    FileContent(
                        mimeType: attachment.mimeType,
                        filename: attachment.filename,
                        data: nil,
                        url: attachment.fileURL,
                        extractedText: attachment.extractedText
                            ?? AttachmentImportPipeline.extractedTextIfSupported(
                                from: attachment.fileURL,
                                mimeType: attachment.mimeType
                            )
                    )
                )
            )
        }

        if !messageText.isEmpty {
            parts.append(.text(messageText))
        }

        return parts
    }

    static func preparedContentForPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        requestedMode: PDFProcessingMode,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        mistralClient: MistralOCRClient?,
        deepSeekClient: DeepInfraDeepSeekOCRClient?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        let shouldSendNativePDF = profile.supportsNativePDF && requestedMode == .native
        guard !shouldSendNativePDF else {
            return PreparedPDFContent(extractedText: nil, additionalParts: [])
        }

        switch requestedMode {
        case .macOSExtract:
            await onStatusUpdate("Extracting PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (macOS): \(attachment.filename)")

            guard let extracted = PDFKitTextExtractor.extractText(
                from: attachment.fileURL,
                maxCharacters: AttachmentConstants.maxPDFExtractedCharacters
            ) else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "macOS Extract")
            }

            var output = "macOS Extract (PDF): \(attachment.filename)\n\n\(extracted)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }

            return PreparedPDFContent(extractedText: output, additionalParts: [])

        case .mistralOCR:
            guard let mistralClient else { throw PDFProcessingError.mistralAPIKeyMissing }

            await onStatusUpdate("OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (Mistral): \(attachment.filename)")

            guard let data = try? Data(contentsOf: attachment.fileURL) else {
                throw PDFProcessingError.fileReadFailed(filename: attachment.filename)
            }

            let includeImageBase64 = profile.supportsVision
            let response = try await mistralClient.ocrPDF(data, includeImageBase64: includeImageBase64)
            let pages = response.pages
                .sorted { $0.index < $1.index }
            var combinedMarkdown = pages
                .map(\.markdown)
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var tablesByID: [String: String] = [:]
            for page in pages {
                for table in page.tables ?? [] {
                    let id = table.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = table.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !id.isEmpty, !content.isEmpty else { continue }
                    tablesByID[id] = content
                    tablesByID[(id as NSString).lastPathComponent] = content
                }
            }

            if !tablesByID.isEmpty {
                combinedMarkdown = MistralOCRMarkdown.replacingTableLinks(from: combinedMarkdown) { id in
                    guard !id.isEmpty else { return "" }
                    if let content = tablesByID[id] { return content }
                    return "[\(id)](\(id))"
                }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !combinedMarkdown.isEmpty else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR")
            }

            let textOnlyMarkdown = MistralOCRMarkdown.removingImageMarkdown(from: combinedMarkdown)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = !textOnlyMarkdown.isEmpty

            var imageParts: [ContentPart] = []
            var attachedImageIDs = Set<String>()
            var totalAttachedImageBytes = 0

            if includeImageBase64 {
                var base64ByID: OrderedDictionary<String, String> = [:]
                var idsInPageOrder = OrderedSet<String>()

                for page in pages {
                    for image in page.images ?? [] {
                        let id = image.id
                        idsInPageOrder.append(id)
                        if let base64 = image.imageBase64, !base64.isEmpty {
                            base64ByID[id] = base64
                        }
                    }
                }

                let referencedIDs = MistralOCRMarkdown.referencedImageIDs(in: combinedMarkdown)
                var orderedIDs = OrderedSet<String>()
                orderedIDs.reserveCapacity(max(referencedIDs.count, idsInPageOrder.count))
                for id in referencedIDs {
                    orderedIDs.append(id)
                }
                for id in idsInPageOrder {
                    orderedIDs.append(id)
                }

                for id in orderedIDs {
                    guard imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach else { break }
                    guard let base64 = base64ByID[id] else { continue }
                    guard let decoded = PDFProcessingUtilities.decodeMistralOCRImageBase64(base64, imageID: id) else { continue }
                    guard let decodedData = decoded.data else { continue }

                    let nextTotal = totalAttachedImageBytes + decodedData.count
                    guard nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes else { break }
                    totalAttachedImageBytes = nextTotal

                    attachedImageIDs.insert(id)
                    imageParts.append(.image(decoded))
                }
            }

            let extractedText: String
            if includeImageBase64 {
                let replaced = MistralOCRMarkdown.replacingImageMarkdown(from: combinedMarkdown) { id in
                    let label = attachedImageIDs.contains(id) ? "Image attached" : "Image omitted"
                    if id.isEmpty { return "[\(label)]" }
                    return "[\(label): \(id)]"
                }
                extractedText = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                extractedText = textOnlyMarkdown
            }

            if !hasText, imageParts.isEmpty {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR (image-only — requires vision)")
            }

            var output = extractedText
            if !hasText, !imageParts.isEmpty {
                output = "Mistral OCR extracted images (no text) from this PDF. See attached images."
            }

            let extractedImageCount = pages.reduce(0) { $0 + (($1.images ?? []).count) }
            let omittedCount = max(0, extractedImageCount - attachedImageIDs.count)
            if includeImageBase64, omittedCount > 0 {
                output += "\n\n[Note: \(omittedCount) extracted image(s) omitted due to size limits.]"
            }

            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            output = "Mistral OCR (Markdown): \(attachment.filename)\n\n\(output)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }
            return PreparedPDFContent(extractedText: output, additionalParts: imageParts)

        case .deepSeekOCR:
            guard let deepSeekClient else { throw PDFProcessingError.deepInfraAPIKeyMissing }

            let includePageImages = profile.supportsVision
            let renderedPages = try PDFKitImageRenderer.renderAllPagesAsJPEG(from: attachment.fileURL)
            let totalPages = max(1, renderedPages.count)

            var pageMarkdown: [String] = []
            pageMarkdown.reserveCapacity(renderedPages.count)

            var imageParts: [ContentPart] = []
            var totalAttachedBytes = 0

            for rendered in renderedPages {
                try Task.checkCancellation()

                await onStatusUpdate("OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (DeepSeek): \(attachment.filename) — page \(rendered.pageIndex + 1)/\(totalPages)")

                let prompt = "Convert this page to Markdown. Preserve layout and tables. Return only the Markdown."
                let raw = try await deepSeekClient.ocrImage(
                    rendered.data,
                    mimeType: rendered.mimeType,
                    prompt: prompt,
                    timeoutSeconds: 120
                )

                let normalized = PDFProcessingUtilities.normalizedDeepSeekOCRMarkdown(raw)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    pageMarkdown.append(normalized)
                }

                if includePageImages,
                   imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach {
                    let nextTotal = totalAttachedBytes + rendered.data.count
                    if nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes {
                        totalAttachedBytes = nextTotal
                        imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
                    }
                }
            }

            let combined = pageMarkdown
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !combined.isEmpty else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "DeepSeek OCR (DeepInfra)")
            }

            var output = combined
            if includePageImages, !imageParts.isEmpty {
                let omitted = max(0, renderedPages.count - imageParts.count)
                output += "\n\n[Note: Attached \(imageParts.count) page image(s) for vision context.]"
                if omitted > 0 {
                    output += "\n[Note: \(omitted) page image(s) omitted due to size limits.]"
                }
            }

            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            output = "DeepSeek OCR (Markdown): \(attachment.filename)\n\n\(output)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }
            return PreparedPDFContent(extractedText: output, additionalParts: imageParts)

        case .native:
            throw PDFProcessingError.nativePDFNotSupported(modelName: profile.modelName)
        }
    }

    static func makeConversationTitle(from userText: String) -> String {
        let firstLine = userText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        return String(trimmed.prefix(48))
    }

    static func fallbackTitleFromMessage(_ message: Message) -> String {
        let text = message.content.compactMap { part -> String? in
            switch part {
            case .text(let value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .file(let file):
                let base = (file.filename as NSString).deletingPathExtension
                let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .image:
                return "Image"
            case .thinking, .redactedThinking, .audio, .video:
                return nil
            }
        }.first

        guard let text else { return "New Chat" }
        return makeConversationTitle(from: text)
    }
}
