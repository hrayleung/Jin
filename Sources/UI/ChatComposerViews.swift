import SwiftUI
import AppKit

// MARK: - Constants

enum AttachmentConstants {
    static let maxDraftAttachments = 8
    static let maxAttachmentBytes = 25 * 1024 * 1024
    static let maxPDFExtractedCharacters = 120_000
    static let maxSpreadsheetExtractedCharacters = 120_000
    static let maxMistralOCRImagesToAttach = 8
    static let maxMistralOCRTotalImageBytes = 12 * 1024 * 1024
}

// MARK: - Error

struct AttachmentImportError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - Draft Attachment

struct DraftAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let fileURL: URL
    let extractedText: String?

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isVideo: Bool { mimeType.hasPrefix("video/") }
    var isAudio: Bool { mimeType.hasPrefix("audio/") }
    var isPDF: Bool { mimeType == "application/pdf" }
}

// MARK: - Draft Attachment Chip

struct DraftAttachmentChip: View {
    let attachment: DraftAttachment
    let onRemove: () -> Void

    private static let maxLabelWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            thumbnailView
                .frame(width: 26, height: 26)

            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .jinSurface(.neutral, cornerRadius: JinRadius.medium)
        .onDrag {
            NSItemProvider(contentsOf: attachment.fileURL)
                ?? NSItemProvider(object: attachment.fileURL as NSURL)
        }
        .help(attachment.filename)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(attachment.filename)
        .contextMenu {
            chipContextMenu
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
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

        if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
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
}

// MARK: - Per-Message MCP Chip

struct PerMessageMCPChip: View {
    let name: String
    let onRemove: () -> Void

    private static let maxLabelWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .background(
            Capsule()
                .fill(JinSemanticColor.accentSurface)
        )
        .overlay(
            Capsule()
                .stroke(JinSemanticColor.selectedStroke, lineWidth: JinStrokeWidth.hairline)
        )
        .help(name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

// MARK: - Composer Control Icon

struct ComposerControlIconLabel: View {
    let systemName: String
    let isActive: Bool
    let badgeText: String?
    let activeColor: Color

    init(systemName: String, isActive: Bool, badgeText: String?, activeColor: Color = .accentColor) {
        self.systemName = systemName
        self.isActive = isActive
        self.badgeText = badgeText
        self.activeColor = activeColor
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? activeColor : Color.secondary)
                .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? JinSemanticColor.separator.opacity(0.45) : Color.clear, lineWidth: JinStrokeWidth.hairline)
                )
                .shadow(color: isActive ? activeColor.opacity(0.35) : Color.clear, radius: 6, x: 0, y: 0)

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, JinSpacing.xSmall)
                    .padding(.vertical, 1)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule()
                            .fill(JinSemanticColor.surface)
                    )
                    .overlay(
                        Capsule()
                            .stroke(JinSemanticColor.separator.opacity(0.7), lineWidth: JinStrokeWidth.hairline)
                    )
                    .offset(x: JinSpacing.xSmall, y: JinSpacing.xSmall)
            }
        }
    }
}

// MARK: - Composer Editor Surface

struct ComposerEditorSurface<Content: View>: View {
    let isFocused: Bool
    let isDropTargeted: Bool
    @ViewBuilder let content: () -> Content

    private var borderColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.7)
        }
        if isFocused {
            return Color.accentColor.opacity(0.34)
        }
        return JinSemanticColor.separator.opacity(0.5)
    }

    private var shadowColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.16)
        }
        if isFocused {
            return Color.accentColor.opacity(0.10)
        }
        return Color.black.opacity(0.04)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        VStack(alignment: .leading, spacing: JinSpacing.small) {
            content()
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .background {
            shape.fill(JinSemanticColor.textSurface)
        }
        .overlay(
            shape.stroke(
                borderColor,
                lineWidth: isDropTargeted ? JinStrokeWidth.emphasized : JinStrokeWidth.hairline
            )
        )
        .shadow(color: shadowColor, radius: isFocused || isDropTargeted ? 12 : 4, x: 0, y: isFocused || isDropTargeted ? 2 : 0)
        .animation(.easeInOut(duration: 0.14), value: isFocused)
        .animation(.easeInOut(duration: 0.14), value: isDropTargeted)
    }
}

// MARK: - Composer Status Summary

struct ComposerStatusSummaryView: View {
    let isPreparingToSend: Bool
    let prepareToSendStatus: String?
    let isRecording: Bool
    let isTranscribing: Bool
    let recordingDurationText: String
    let transcribingStatusText: String

    @ViewBuilder
    var body: some View {
        if isPreparingToSend, let prepareToSendStatus {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(prepareToSendStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else if isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Recording… \(recordingDurationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else if isTranscribing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(transcribingStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Collapsed Composer Bar

struct CollapsedComposerBar: View {
    let hasContent: Bool
    let onExpand: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        Button(action: onExpand) {
            HStack(spacing: JinSpacing.medium) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text(hasContent ? "Continue typing\u{2026}" : "Type a message\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, JinSpacing.large)
            .padding(.vertical, 10)
            .frame(maxWidth: 800)
            .background {
                shape.fill(.regularMaterial)
            }
            .overlay(
                shape.stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show message composer")
        .accessibilityHint("Double-click to expand the message input area")
    }
}
