import Foundation

/// Pure helpers for the composer's source-video URL affordance. Deliberately
/// SwiftUI-free so label formatting and validation copy stay unit-testable
/// without standing up a view.
enum ComposerRemoteVideoURLSupport {
    static let maxCompactLabelLength = 64

    /// Chip label: the file name when the link has one, else the host, else the
    /// raw text. Query strings are dropped — signed CDN links are token noise.
    static func compactLabel(for raw: String) -> String {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return "" }

        guard let components = URLComponents(string: trimmed) else {
            return clamped(trimmed)
        }

        if let lastPathComponent = components.path.split(separator: "/").last {
            let decoded = String(lastPathComponent).removingPercentEncoding ?? String(lastPathComponent)
            if !decoded.isEmpty {
                return clamped(decoded)
            }
        }

        if let host = components.host, !host.isEmpty {
            return clamped(host)
        }

        return clamped(trimmed)
    }

    /// `nil` when the text is empty or a valid http(s) link. Validation is
    /// delegated to the send path's own guard so the editor can never accept a
    /// URL that `sendMessage` would later reject.
    static func validationErrorMessage(for raw: String) -> String? {
        do {
            _ = try ChatMessagePreparationSupport.resolvedRemoteVideoInputURL(
                from: raw.trimmed,
                supportsExplicitRemoteVideoURLInput: true
            )
            return nil
        } catch {
            return "Enter a public http(s) link to a video file."
        }
    }

    static func helpText(for raw: String) -> String {
        guard let trimmed = raw.trimmedNonEmpty else { return "Add a source video URL" }
        return "Source video: \(trimmed)"
    }

    private static func clamped(_ value: String) -> String {
        String(value.prefix(maxCompactLabelLength))
    }
}
