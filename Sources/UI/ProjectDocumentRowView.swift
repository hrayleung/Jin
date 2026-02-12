import SwiftUI

struct ProjectDocumentRowView: View {
    let document: ProjectDocumentEntity
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: JinSpacing.medium) {
            documentIcon
                .frame(width: 28, height: 28)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text(document.filename)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: JinSpacing.small) {
                    Text(formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if document.processingStatus == "ready",
                       let text = document.extractedText {
                        Text("\(estimateTokenCount(text)) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    statusBadge
                }
            }

            Spacer(minLength: 0)

            if document.processingStatus == "extracting" || document.processingStatus == "indexing" {
                ProgressView()
                    .controlSize(.small)
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Remove document")
        }
        .padding(.vertical, JinSpacing.xSmall)
    }

    // MARK: - Components

    @ViewBuilder
    private var documentIcon: some View {
        let ext = (document.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            Image(systemName: "doc.fill")
                .font(.system(size: 16, weight: .semibold))
        case "md", "markdown":
            Image(systemName: "doc.text.fill")
                .font(.system(size: 16, weight: .semibold))
        case "json":
            Image(systemName: "curlybraces")
                .font(.system(size: 16, weight: .semibold))
        case "csv", "tsv":
            Image(systemName: "tablecells.fill")
                .font(.system(size: 16, weight: .semibold))
        default:
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .semibold))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch document.processingStatus {
        case "pending":
            Text("Pending")
                .font(.caption2)
                .jinTagStyle()
        case "extracting":
            Text("Extracting…")
                .font(.caption2)
                .jinTagStyle()
        case "indexing":
            Text("Indexing…")
                .font(.caption2)
                .jinTagStyle()
        case "ready":
            Text("Ready")
                .font(.caption2)
                .foregroundStyle(.green)
        case "failed":
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text("Failed")
                    .font(.caption2)
            }
            .foregroundStyle(.red)
            .help(document.processingError ?? "Processing failed")
        default:
            EmptyView()
        }
    }

    private var statusColor: Color {
        switch document.processingStatus {
        case "ready": return .accentColor
        case "failed": return .red
        default: return .secondary
        }
    }

    // MARK: - Formatting

    private var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: document.fileSizeBytes, countStyle: .file)
    }

    private func estimateTokenCount(_ text: String) -> Int {
        Int(ceil(Double(text.count) / 3.5))
    }
}
