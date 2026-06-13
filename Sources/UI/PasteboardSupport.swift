import AppKit

enum PasteboardSupport {
    /// Clears the general pasteboard and writes a plain string.
    @MainActor
    static func writeString(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
