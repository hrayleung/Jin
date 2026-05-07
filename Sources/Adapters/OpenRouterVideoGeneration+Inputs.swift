import Foundation

extension OpenRouterAdapter {
    func videoGenerationPrompt(from messages: [Message]) throws -> String {
        for message in messages.reversed() where message.role == .user {
            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                return value.trimmedNonEmpty
            }
            .joined(separator: "\n\n")

            if let text = text.trimmedNonEmpty {
                return text
            }
        }

        throw LLMError.invalidRequest(message: "OpenRouter video generation requires a text prompt.")
    }

    func videoGenerationImages(from messages: [Message]) -> [ImageContent] {
        if let latestUserImages = latestUserImageInputs(from: messages), !latestUserImages.isEmpty {
            return latestUserImages
        }

        for message in messages.reversed() where message.role == .assistant || message.role == .user {
            let images = imageInputs(in: message)
            if !images.isEmpty {
                return images
            }
        }

        return []
    }

    func latestUserImageInputs(from messages: [Message]) -> [ImageContent]? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        let images = imageInputs(in: latestUserMessage)
        return images.isEmpty ? nil : images
    }

    func imageInputs(in message: Message) -> [ImageContent] {
        message.content.compactMap { part in
            guard case .image(let image) = part else { return nil }
            return image
        }
    }
}
