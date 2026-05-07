import SwiftUI
import AppKit

private enum DraftAttachmentThumbnailProvider {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    static func cacheKey(for url: URL) -> NSString {
        url.standardizedFileURL.path as NSString
    }

    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: cacheKey(for: url))
    }

    static func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: cacheKey(for: url))
    }
}

private struct DraftAttachmentThumbnailView: View {
    let attachment: DraftAttachment

    @State private var image: NSImage?

    var body: some View {
        Group {
            if attachment.isImage {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            } else if attachment.isAudio {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
            } else if attachment.isVideo {
                Image(systemName: "video")
                    .foregroundStyle(.secondary)
            } else if attachment.isPDF {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: attachment.id) {
            await loadImageIfNeeded()
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard attachment.isImage else {
            image = nil
            return
        }

        if let cached = DraftAttachmentThumbnailProvider.cachedImage(for: attachment.fileURL) {
            image = cached
            return
        }

        let url = attachment.fileURL
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value

        guard !Task.isCancelled,
              let data,
              let loadedImage = NSImage(data: data) else {
            image = nil
            return
        }

        DraftAttachmentThumbnailProvider.store(loadedImage, for: url)
        image = loadedImage
    }
}

struct DraftAttachmentChip: View {
    let attachment: DraftAttachment
    let onRemove: () -> Void

    private static let maxLabelWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            DraftAttachmentThumbnailView(attachment: attachment)
                .frame(width: 26, height: 26)

            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.filename)")
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .jinSurface(.neutral, cornerRadius: JinRadius.medium)
        .help(attachment.filename)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.filename)
        .contextMenu {
            chipContextMenu
        }
    }

    @ViewBuilder
    private var chipContextMenu: some View {
        Button {
            NSWorkspace.shared.open(attachment.fileURL)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([attachment.fileURL])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        if attachment.isImage {
            Button {
                copyImageToPasteboard()
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(attachment.fileURL.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            onRemove()
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func copyImageToPasteboard() {
        guard let image = DraftAttachmentThumbnailProvider.cachedImage(for: attachment.fileURL)
            ?? NSImage(contentsOf: attachment.fileURL) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
