import AppKit
import SwiftUI

struct ToolOutputFileActionRow: View {
    let rawOutputPath: String

    private var fileURL: URL? {
        let trimmed = rawOutputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        if let fileURL {
            HStack(spacing: JinSpacing.small) {
                Button("Open Full Output") {
                    NSWorkspace.shared.open(fileURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text("Full output file is unavailable.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)

                Text(rawOutputPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}
