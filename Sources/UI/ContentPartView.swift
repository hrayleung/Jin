import SwiftUI
import AppKit
import AVFoundation
import AVKit

// MARK: - JinAVPlayerView (AppKit subclass with context menu)

/// Custom AVPlayerView that provides a native context menu with Reveal in Finder,
/// since SwiftUI `.contextMenu` does not receive right-click events from NSViewRepresentable.
private final class JinAVPlayerView: AVPlayerView {
    var mediaURL: URL?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url = mediaURL else { return nil }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open", action: #selector(openMedia), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(openItem)

        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        revealItem.target = self
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(revealItem)

        menu.addItem(.separator())

        if url.isFileURL {
            let copyItem = NSMenuItem(title: "Copy Path", action: #selector(copyPathOrURL), keyEquivalent: "")
            copyItem.target = self
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copyItem)
        } else {
            let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyPathOrURL), keyEquivalent: "")
            copyItem.target = self
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copyItem)
        }

        return menu
    }

    @objc private func openMedia() {
        guard let url = mediaURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealInFinder() {
        guard let url = mediaURL else { return }
        if url.isFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            Task {
                if let localURL = await MessageMediaAssetPersistenceSupport.persistRemoteVideoToDisk(from: url) {
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([localURL])
                    }
                }
            }
        }
    }

    @objc private func copyPathOrURL() {
        guard let url = mediaURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
    }
}

// MARK: - VideoPlayerView (NSViewRepresentable)

/// Wraps JinAVPlayerView to provide video playback with a native context menu.
private struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> JinAVPlayerView {
        let view = JinAVPlayerView()
        view.player = AVPlayer(url: url)
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.mediaURL = url
        return view
    }

    func updateNSView(_ nsView: JinAVPlayerView, context: Context) {
        if (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            nsView.player = AVPlayer(url: url)
            nsView.mediaURL = url
        }
    }
}

// MARK: - Content Part View

struct ContentPartView: View {
    let part: ContentPart
    var isUser: Bool = false
    var deferCodeHighlightUpgrade: Bool = false

    var body: some View {
        switch part {
        case .text(let text):
            MessageTextView(
                text: text,
                mode: isUser ? .plainText : .markdown,
                deferCodeHighlightUpgrade: (!isUser && deferCodeHighlightUpgrade)
            )

        case .thinking(let thinking):
            ThinkingBlockView(thinking: thinking)

        case .redactedThinking:
            EmptyView()

        case .image(let image):
            let fileURL = (image.url?.isFileURL == true) ? image.url : nil

            if let data = image.data, let nsImage = NSImage(data: data) {
                renderedImage(nsImage, fileURL: fileURL, imageData: data, mimeType: image.mimeType)
            } else if let fileURL, let nsImage = NSImage(contentsOf: fileURL) {
                renderedImage(nsImage, fileURL: fileURL, imageData: nil, mimeType: image.mimeType)
            } else if let url = image.remoteURL {
                RemoteMessageImageView(image: image, url: url, isUser: isUser)
            }

        case .video(let video):
            renderedVideo(video)

        case .file(let file):
            fileContentView(file)

        case .audio:
            Label("Audio content", systemImage: "waveform")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }

    @ViewBuilder
    private func fileContentView(_ file: FileContent) -> some View {
        let row = HStack {
            Image(systemName: "doc")
            Text(file.filename)
        }
        .padding(JinSpacing.small)
        .jinSurface(.neutral, cornerRadius: JinRadius.small)

        if let url = file.url {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .help("Open \(file.filename)")
            .onDrag {
                NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
            }
            .contextMenu {
                fileContextMenu(url: url, filename: file.filename, extractedText: file.extractedText)
            }
        } else {
            row
                .contextMenu {
                    filenameOnlyContextMenu(filename: file.filename, extractedText: file.extractedText)
                }
        }
    }

    @ViewBuilder
    private func fileContextMenu(url: URL, filename: String, extractedText: String?) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(extractedText)
    }

    @ViewBuilder
    private func filenameOnlyContextMenu(filename: String, extractedText: String?) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(extractedText)
    }

    @ViewBuilder
    private func extractedTextCopyButton(_ extractedText: String?) -> some View {
        if let extracted = extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !extracted.isEmpty {
            Divider()

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(extracted, forType: .string)
            } label: {
                Label("Copy Extracted Text", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private func renderedVideo(_ video: VideoContent) -> some View {
        if let fileURL = video.url, fileURL.isFileURL {
            VideoPlayerView(url: fileURL)
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        } else if let url = video.url {
            VideoPlayerView(url: url)
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        } else if let data = video.data {
            Label("Video data (\(data.count) bytes)", systemImage: "video")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        } else {
            Label("Video", systemImage: "video")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }

    @ViewBuilder
    private func renderedImage(_ image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
        if isUser {
            userImageThumbnail(image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
        } else {
            fullSizeImage(image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
        }
    }

    @ViewBuilder
    private func userImageThumbnail(_ image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: JinStrokeWidth.hairline)
            )
            .onTapGesture {
                if let fileURL {
                    NSWorkspace.shared.open(fileURL)
                } else if let savedURL = MessageMediaAssetPersistenceSupport.persistImageToDisk(
                    data: imageData,
                    image: image,
                    mimeType: mimeType
                ) {
                    NSWorkspace.shared.open(savedURL)
                }
            }
            .onDrag {
                if let fileURL {
                    return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: fileURL as NSURL)
                }
                return NSItemProvider(object: image)
            }
            .contextMenu {
                imageContextMenu(image: image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
            }
    }

    @ViewBuilder
    private func fullSizeImage(_ image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 500)
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            .onDrag {
                if let fileURL {
                    return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: fileURL as NSURL)
                }
                return NSItemProvider(object: image)
            }
            .contextMenu {
                imageContextMenu(image: image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
            }
    }

    @ViewBuilder
    private func imageContextMenu(image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
        if let fileURL {
            Button {
                NSWorkspace.shared.open(fileURL)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
        }

        Button {
            if let fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } else if let savedURL = MessageMediaAssetPersistenceSupport.persistImageToDisk(
                data: imageData,
                image: image,
                mimeType: mimeType
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
            }
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        } label: {
            Label("Copy Image", systemImage: "doc.on.doc")
        }

        if let fileURL {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(fileURL.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }
}
