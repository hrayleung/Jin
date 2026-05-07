import Foundation

extension XAIAdapter {

    // MARK: - Media Prompt Building

    func mediaPrompt(from messages: [Message], mode: XAIMediaPromptSupport.EditMode) throws -> String {
        try XAIMediaPromptSupport.prompt(from: messages, mode: mode)
    }

    func userTextPrompts(from messages: [Message]) -> [String] {
        XAIMediaPromptSupport.userTextPrompts(from: messages)
    }

    // MARK: - Image URL Extraction

    func imageURLForImageGeneration(from messages: [Message]) throws -> String? {
        try XAIMediaImageSupport.imageURLForImageGeneration(from: messages)
    }

    func imageURLString(_ image: ImageContent) throws -> String? {
        try XAIMediaImageSupport.imageURLString(image)
    }

    // MARK: - Image Output Resolution

    func resolveImageOutputs(from items: [XAIMediaItem]) -> [ImageContent] {
        XAIMediaImageSupport.resolveImageOutputs(from: items)
    }

    func inferImageMIMEType(from url: URL) -> String? {
        XAIMediaImageSupport.inferImageMIMEType(from: url)
    }
}
