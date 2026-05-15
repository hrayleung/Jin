import AppKit
import SwiftUI

extension CompactComposerOverlayView {
    @ViewBuilder
    var leftColumn: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            perMessageMCPChipsRow
            quoteCardsRow
            attachmentChipsRow
            remoteVideoInputRow
            composerTextEditor
            composerActionBar
            prepareStatusRow
            speechStatusRow
        }
    }

    @ViewBuilder
    var composerActionBar: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            controlsRow()

            if let contextUsageEstimate {
                ContextUsageIndicatorView(
                    estimate: contextUsageEstimate,
                    modelName: currentModelName
                )
                .equatable()
                .padding(.bottom, 2)
            }

            hideButton
            expandButton
            sendButton
        }
    }

    @ViewBuilder
    var perMessageMCPChipsRow: some View {
        if !perMessageMCPChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JinSpacing.small) {
                    ForEach(perMessageMCPChips) { chip in
                        PerMessageMCPChip(
                            name: chip.name,
                            onRemove: { onRemovePerMessageMCPServer(chip.id) }
                        )
                    }
                }
                .padding(.horizontal, JinSpacing.xSmall)
            }
        }
    }

    @ViewBuilder
    var quoteCardsRow: some View {
        if !draftQuotes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: JinSpacing.small) {
                    ForEach(draftQuotes) { quote in
                        ComposerQuoteCardView(quote: quote) {
                            onRemoveQuote(quote)
                        }
                        .equatable()
                        .transition(ComposerQuoteCardView.transition(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, JinSpacing.xSmall)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    var attachmentChipsRow: some View {
        if !draftAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JinSpacing.small) {
                    ForEach(draftAttachments) { attachment in
                        DraftAttachmentChip(
                            attachment: attachment,
                            onRemove: { onRemoveAttachment(attachment) }
                        )
                    }
                }
                .padding(.horizontal, JinSpacing.xSmall)
            }
        }
    }

    @ViewBuilder
    var remoteVideoInputRow: some View {
        if showsRemoteVideoURLField {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Source Video URL", text: $remoteVideoURLText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .disabled(isBusy)

                if !trimmedRemoteVideoURLText.isEmpty {
                    Button {
                        remoteVideoURLText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear source video URL")
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .jinSurface(.subtle, cornerRadius: JinRadius.medium)
        }
    }

    @ViewBuilder
    var composerTextEditor: some View {
        DroppableTextEditor(
            text: $messageText,
            isDropTargeted: $isComposerDropTargeted,
            isFocused: $isComposerFocused,
            placeholder: "Write a message",
            font: NSFont.preferredFont(forTextStyle: .body),
            useCommandEnterToSubmit: sendWithCommandEnter,
            onDropFileURLs: onDropFileURLs,
            onDropImages: onDropImages,
            onSubmit: onSubmit,
            onCancel: onCancel,
            onContentHeightChanged: updateComposerTextContentHeight,
            onInterceptKeyDown: onInterceptKeyDown
        )
        .frame(height: composerTextContentHeight)
    }

    @ViewBuilder
    var prepareStatusRow: some View {
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
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    var speechStatusRow: some View {
        if isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Recording… \(recordingDurationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
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
            .padding(.top, 2)
        }
    }

    var trimmedRemoteVideoURLText: String {
        remoteVideoURLText.trimmed
    }
}
