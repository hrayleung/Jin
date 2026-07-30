import AppKit
import ImageIO
import SwiftUI

extension ContentPartView {
    func renderedImage(_ image: RenderedImageContent) -> some View {
        HistoricalMessageImageView(
            image: image,
            isUser: isUser,
            payloadResolver: payloadResolver
        )
    }
}

private enum MessageImageThumbnailProvider {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        // Entries are decoded bitmaps up to ~1400px on the long edge (~8 MB
        // each), so a count limit alone allows ~750 MB resident. Bound bytes
        // too; inserts pass the bitmap size as the cost.
        cache.totalCostLimit = 192 * 1024 * 1024
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
                return ImageDownsampler.image(at: localFileURL, maxPixelSize: maxPixelSize)
            }
            if let sourceData {
                return ImageDownsampler.image(data: sourceData, maxPixelSize: maxPixelSize)
            }
            return nil
        }.value

        guard !Task.isCancelled else { return }

        renderedImageData = sourceData
        renderedImage = loadedImage
        loadFailed = loadedImage == nil

        if let loadedImage {
            MessageImageThumbnailProvider.cache.setObject(
                loadedImage,
                forKey: cacheKey,
                cost: ImageDownsampler.estimatedBitmapCost(of: loadedImage)
            )
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
                        .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
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
                PasteboardSupport.writeString(fileURL.path)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

}
