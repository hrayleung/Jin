import SwiftUI
import AppKit
import Kingfisher

struct RemoteMessageImageView: View {
    let image: ImageContent
    let url: URL
    var isUser: Bool = false

    @State private var loadFailed = false

    var body: some View {
        Group {
            if loadFailed {
                fallbackView
            } else if isUser {
                KFImage(source: .network(KF.ImageResource(downloadURL: url)))
                    .placeholder { _ in userPlaceholderView }
                    .cancelOnDisappear(true)
                    .fade(duration: 0.15)
                    .onSuccess { _ in loadFailed = false }
                    .onFailure { _ in loadFailed = true }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: JinStrokeWidth.hairline)
                    )
                    .onTapGesture {
                        NSWorkspace.shared.open(url)
                    }
            } else {
                KFImage(source: .network(KF.ImageResource(downloadURL: url)))
                    .placeholder { _ in placeholderView }
                    .cancelOnDisappear(true)
                    .fade(duration: 0.15)
                    .onSuccess { _ in loadFailed = false }
                    .onFailure { _ in loadFailed = true }
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500)
                    .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            }
        }
        .task(id: url) {
            loadFailed = false
        }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.absoluteString, forType: .string)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }

            if image.assetDisposition == .externalReference {
                Divider()

                Text("External reference")
            }
        }
    }

    private var userPlaceholderView: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: 80, height: 80)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }

    private var placeholderView: some View {
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

    private var fallbackView: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Unable to load image preview", systemImage: "photo")
                .font(.callout.weight(.medium))
            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .frame(maxWidth: 500, alignment: .leading)
        .padding(JinSpacing.medium)
        .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }
}
