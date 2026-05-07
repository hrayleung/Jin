import Foundation

enum XAIVideoInputSupport {
    static func videoInputForVideoGeneration(from messages: [Message]) -> VideoContent? {
        if let latestUserVideo = latestUserVideoInput(from: messages) {
            return latestUserVideo
        }

        if let latestUserRemoteVideo = latestUserMentionedRemoteVideoInput(from: messages) {
            return latestUserRemoteVideo
        }

        if let assistantVideo = firstVideoInput(from: messages, roles: [.assistant]) {
            return assistantVideo
        }

        if let olderUserVideo = firstVideoInput(from: messages, roles: [.user]) {
            return olderUserVideo
        }

        return firstMentionedRemoteVideoInput(from: messages, roles: [.user])
    }

    static func remoteVideoURLString(_ video: VideoContent) -> String? {
        guard let url = video.url, isHTTPRemoteURL(url) else {
            return nil
        }
        return url.absoluteString
    }

    static func firstRemoteVideoURLMention(in text: String) -> URL? {
        guard let trimmed = text.trimmedNonEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        for match in detector.matches(in: trimmed, options: [], range: range) {
            guard let url = match.url,
                  isHTTPRemoteURL(url),
                  looksLikeVideoRemoteURL(url) else {
                continue
            }
            return url
        }

        return nil
    }

    static func looksLikeVideoRemoteURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let knownVideoExtensions: Set<String> = [
            "mp4", "m4v", "mov", "webm", "avi", "mkv",
            "mpeg", "mpg", "wmv", "flv", "3gp", "3gpp"
        ]
        if knownVideoExtensions.contains(ext) {
            return true
        }

        let lower = url.absoluteString.lowercased()
        let markers = [
            ".mp4", ".m4v", ".mov", ".webm", ".avi", ".mkv",
            ".mpeg", ".mpg", ".wmv", ".flv", ".3gp", ".3gpp",
            "/video", "-video", "_video", "video="
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func latestUserVideoInput(from messages: [Message]) -> VideoContent? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstVideoInput(in: latestUserMessage)
    }

    private static func firstVideoInput(in message: Message) -> VideoContent? {
        for part in message.content {
            if case .video(let video) = part {
                return video
            }
        }
        return nil
    }

    private static func firstVideoInput(from messages: [Message], roles: [MessageRole]) -> VideoContent? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let video = firstVideoInput(in: message) {
                return video
            }
        }
        return nil
    }

    private static func latestUserMentionedRemoteVideoInput(from messages: [Message]) -> VideoContent? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstMentionedRemoteVideoInput(in: latestUserMessage)
    }

    private static func firstMentionedRemoteVideoInput(from messages: [Message], roles: [MessageRole]) -> VideoContent? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let video = firstMentionedRemoteVideoInput(in: message) {
                return video
            }
        }
        return nil
    }

    private static func firstMentionedRemoteVideoInput(in message: Message) -> VideoContent? {
        for part in message.content {
            guard case .text(let text) = part,
                  let url = firstRemoteVideoURLMention(in: text) else {
                continue
            }

            let inferred = VideoAttachmentUtility.resolveVideoFormat(contentType: nil, url: url)
            return VideoContent(mimeType: inferred.mimeType, data: nil, url: url, assetDisposition: .externalReference)
        }
        return nil
    }

    private static func isHTTPRemoteURL(_ url: URL) -> Bool {
        guard !url.isFileURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }
}
