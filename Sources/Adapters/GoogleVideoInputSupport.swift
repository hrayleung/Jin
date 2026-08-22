import Foundation

/// Encodes a `.video` part for Google's `generateContent` surfaces (Gemini AI Studio and
/// Vertex AI), which accept video three different ways depending on where the bytes live.
///
/// The plain `inlineDataPart` helper handles only the first of those and returns nil for
/// everything else, so a remote video URL used to vanish from the request without a trace —
/// and the composer offers exactly such a field for any model claiming `.videoInput`.
///
/// Verified against AI Studio `:generateContent` on 2026-08-22:
/// - local bytes / file URL → `inlineData`, reads correctly
/// - `https://www.youtube.com/watch?v=…` → `fileData.fileUri`, 200 with a real description
///   of the clip (Google fetches YouTube itself)
/// - any other `https://…mp4` → `400 Cannot fetch content from the provided URL`
///
/// `gs://` is Vertex-only (Vertex reads Cloud Storage directly; AI Studio has no such
/// notion) and is documented rather than probed — there are no Vertex credentials on hand.
enum GoogleVideoInputSupport {
    /// Hosts whose watch/share links Google resolves server-side.
    private static let youTubeHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "www.youtu.be"
    ]

    static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return youTubeHosts.contains(host)
    }

    static func isGoogleCloudStorageURI(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "gs"
    }

    /// Returns the encoded part, or nil when Google cannot reach the video at all — the
    /// caller must then emit `remoteVideoNotFetchableNotice` rather than skip the part.
    static func videoPart(
        _ video: VideoContent,
        allowsGoogleCloudStorageURI: Bool
    ) throws -> [String: Any]? {
        if let inline = try GeminiModelConstants.inlineDataPart(
            mimeType: video.mimeType,
            data: video.data,
            url: video.url
        ) {
            return inline
        }

        guard let url = video.url else { return nil }

        if isYouTubeURL(url) {
            // No mimeType: YouTube links carry no file extension to infer one from, and
            // Google resolves the media type itself. Sending a guessed `video/mp4` is
            // accepted too, but the bare form is what the docs show.
            return ["fileData": ["fileUri": url.absoluteString]]
        }

        if allowsGoogleCloudStorageURI, isGoogleCloudStorageURI(url) {
            return [
                "fileData": [
                    "mimeType": video.mimeType,
                    "fileUri": url.absoluteString
                ]
            ]
        }

        return nil
    }
}
