import AppKit
import SwiftUI

struct ToolOutputFileActionRowView: View {
    let rawOutputPath: String
    @State private var cachedFileURL: URL?

    private var normalizedFileURL: URL? {
        let trimmed = rawOutputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    var body: some View {
        Group {
            if let fileURL = cachedFileURL {
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
        .onAppear {
            refreshCachedFileURL()
        }
        .onChange(of: rawOutputPath) { _, _ in
            refreshCachedFileURL()
        }
    }

    private func refreshCachedFileURL() {
        guard let normalizedFileURL,
              FileManager.default.fileExists(atPath: normalizedFileURL.path) else {
            cachedFileURL = nil
            return
        }
        cachedFileURL = normalizedFileURL
    }
}
