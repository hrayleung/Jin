import SwiftUI
import AppKit
import AVFoundation
import AVKit
import ImageIO
import CryptoKit

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

struct RenderedMessagePayloadResolver {
    let loadImageData: @Sendable (DeferredMessagePartReference) async -> Data?
    let loadFileExtractedText: @Sendable (DeferredMessagePartReference) async -> String?

    static let noop = RenderedMessagePayloadResolver(
        loadImageData: { _ in nil },
        loadFileExtractedText: { _ in nil }
    )
}

enum MessageImageCacheKeySupport {
    static func inlineDataFingerprint(_ data: Data) -> String {
        SHA256.hash(data: data)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum MessageImageThumbnailProvider {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        return cache
    }()

    static func cacheKey(for image: RenderedImageContent, isUser: Bool) -> NSString {
        let sizeBucket = isUser ? "thumb" : "full"
        if let fileURL = image.url, fileURL.isFileURL {
            return "file|\(sizeBucket)|\(fileURL.standardizedFileURL.path)" as NSString
        }
        if let source = image.deferredSource {
            return "deferred|\(sizeBucket)|\(source.messageID.uuidString)|\(source.partIndex)" as NSString
        }
        if let data = image.inlineData {
            return "inline|\(sizeBucket)|\(MessageImageCacheKeySupport.inlineDataFingerprint(data))" as NSString
        }
        return "unknown|\(sizeBucket)|\(image.mimeType)" as NSString
    }
}

private struct HistoricalMessageImageView: View {
    let image: RenderedImageContent
    let isUser: Bool
    let payloadResolver: RenderedMessagePayloadResolver

    @State private var renderedImage: NSImage?
    @State private var renderedImageData: Data?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let url = image.remoteURL {
                RemoteMessageImageView(image: image, url: url, isUser: isUser)
            } else if let renderedImage {
                renderedImageBody(renderedImage)
            } else if loadFailed {
                fallbackView
            } else {
                placeholderView
            }
        }
        .task(id: MessageImageThumbnailProvider.cacheKey(for: image, isUser: isUser)) {
            await loadImageIfNeeded()
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard image.remoteURL == nil else { return }

        let cacheKey = MessageImageThumbnailProvider.cacheKey(for: image, isUser: isUser)
        if let cached = MessageImageThumbnailProvider.cache.object(forKey: cacheKey) {
            renderedImage = cached
            loadFailed = false
            return
        }

        let maxPixelSize = isUser ? 240 : 1_400
        let localFileURL = image.url?.isFileURL == true ? image.url : nil
        var sourceData = image.inlineData

        if sourceData == nil, let deferredSource = image.deferredSource {
            sourceData = await payloadResolver.loadImageData(deferredSource)
        }

        let loadedImage = await Task.detached(priority: .utility) {
            if let localFileURL {
                return Self.downsampledImage(at: localFileURL, maxPixelSize: maxPixelSize)
            }
            if let sourceData {
                return Self.downsampledImage(data: sourceData, maxPixelSize: maxPixelSize)
            }
            return nil
        }.value

        guard !Task.isCancelled else { return }

        renderedImageData = sourceData
        renderedImage = loadedImage
        loadFailed = loadedImage == nil

        if let loadedImage {
            MessageImageThumbnailProvider.cache.setObject(loadedImage, forKey: cacheKey)
        }
    }

    @ViewBuilder
    private func renderedImageBody(_ renderedImage: NSImage) -> some View {
        if isUser {
            Image(nsImage: renderedImage)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: JinStrokeWidth.hairline)
                )
                .onTapGesture(perform: openImage)
                .onDrag(dragProvider)
                .contextMenu { imageContextMenu(renderedImage) }
        } else {
            Image(nsImage: renderedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 500)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                .onTapGesture(perform: openImage)
                .onDrag(dragProvider)
                .contextMenu { imageContextMenu(renderedImage) }
        }
    }

    private var placeholderView: some View {
        Group {
            if isUser {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 80, height: 80)
                    .jinSurface(.neutral, cornerRadius: JinRadius.small)
            } else {
                VStack(spacing: JinSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading image…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 500, minHeight: 120)
                .padding(JinSpacing.medium)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
            }
        }
    }

    private var fallbackView: some View {
        Label("Unable to load image preview", systemImage: "photo")
            .padding(JinSpacing.small)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }

    private func openImage() {
        if let fileURL = image.url, fileURL.isFileURL {
            NSWorkspace.shared.open(fileURL)
            return
        }

        guard let renderedImage,
              let savedURL = MessageMediaAssetPersistenceSupport.persistImageToDisk(
                data: renderedImageData,
                image: renderedImage,
                mimeType: image.mimeType
              ) else { return }

        NSWorkspace.shared.open(savedURL)
    }

    private func dragProvider() -> NSItemProvider {
        if let fileURL = image.url, fileURL.isFileURL {
            return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: fileURL as NSURL)
        }
        if let renderedImage {
            return NSItemProvider(object: renderedImage)
        }
        return NSItemProvider()
    }

    @ViewBuilder
    private func imageContextMenu(_ renderedImage: NSImage) -> some View {
        if let fileURL = image.url, fileURL.isFileURL {
            Button {
                NSWorkspace.shared.open(fileURL)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        } else {
            Button {
                if let savedURL = MessageMediaAssetPersistenceSupport.persistImageToDisk(
                    data: renderedImageData,
                    image: renderedImage,
                    mimeType: image.mimeType
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                }
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }

        Divider()

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([renderedImage])
        } label: {
            Label("Copy Image", systemImage: "doc.on.doc")
        }

        if let fileURL = image.url, fileURL.isFileURL {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(fileURL.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

    private nonisolated static func downsampledImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    private nonisolated static func downsampledImage(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    private nonisolated static func thumbnailImage(from source: CGImageSource, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

struct ContentPartView: View {
    let part: RenderedContentPart
    var isUser: Bool = false
    var deferCodeHighlightUpgrade: Bool = false
    var forceNativeText: Bool = false
    var payloadResolver: RenderedMessagePayloadResolver = .noop
    var normalizeMarkdownForModelID: String? = nil
    var selectionMessageID: UUID? = nil
    var selectionContextThreadID: UUID? = nil
    var selectionAnchorID: String? = nil
    var persistedHighlights: [MessageHighlightSnapshot] = []
    var selectionActions: MessageTextSelectionActions = .none

    var body: some View {
        switch part {
        case .text(let text):
            MessageTextView(
                text: text,
                mode: (isUser || forceNativeText) ? .plainText : .markdown,
                deferCodeHighlightUpgrade: (!isUser && deferCodeHighlightUpgrade),
                selectionMessageID: selectionMessageID,
                selectionContextThreadID: selectionContextThreadID,
                selectionAnchorID: selectionAnchorID,
                persistedHighlights: persistedHighlights,
                selectionActions: selectionActions,
                normalizeMarkdownForModelID: normalizeMarkdownForModelID
            )

        case .quote(let quote):
            MessageQuoteCardView(quote: quote)

        case .thinking(let thinking):
            ThinkingBlockView(thinking: thinking)

        case .redactedThinking:
            EmptyView()

        case .image(let image):
            HistoricalMessageImageView(
                image: image,
                isUser: isUser,
                payloadResolver: payloadResolver
            )

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
    private func fileContentView(_ file: RenderedFileContent) -> some View {
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
                fileContextMenu(file: file, url: url)
            }
        } else {
            row
                .contextMenu {
                    filenameOnlyContextMenu(file: file)
                }
        }
    }

    @ViewBuilder
    private func fileContextMenu(file: RenderedFileContent, url: URL) -> some View {
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
            pasteboard.setString(file.filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(file)
    }

    @ViewBuilder
    private func filenameOnlyContextMenu(file: RenderedFileContent) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(file.filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(file)
    }

    @ViewBuilder
    private func extractedTextCopyButton(_ file: RenderedFileContent) -> some View {
        if file.hasExtractedText {
            Divider()

            Button {
                Task {
                    await copyExtractedText(for: file)
                }
            } label: {
                Label("Copy Extracted Text", systemImage: "doc.on.doc")
            }
        }
    }

    @MainActor
    private func copyExtractedText(for file: RenderedFileContent) async {
        let extracted: String?
        if let immediate = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !immediate.isEmpty {
            extracted = immediate
        } else if let deferredSource = file.deferredSource {
            extracted = await payloadResolver.loadFileExtractedText(deferredSource)
        } else {
            extracted = nil
        }

        guard let extracted,
              !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(extracted, forType: .string)
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
}
