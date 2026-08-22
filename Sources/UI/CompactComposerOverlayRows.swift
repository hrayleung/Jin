import AppKit
import SwiftUI

extension CompactComposerOverlayView {
    @ViewBuilder
    var leftColumn: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            perMessageMCPChipsRow
            quoteCardsRow
            attachmentChipsRow
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
        if !draftAttachments.isEmpty || showsRemoteVideoURLChip {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JinSpacing.small) {
                    // Leads the row: there is at most one, and it is the
                    // subject of the turn rather than one of N attachments.
                    if showsRemoteVideoURLChip {
                        ComposerRemoteVideoURLChip(
                            urlText: remoteVideoURLText,
                            onRemove: onRemoveRemoteVideoURL
                        )
                    }

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
        .help(shortcutsStore.helpText("Message composer", for: .focusComposer))
        .shortcutHint(.focusComposer, placement: .above)
    }

    @ViewBuilder
    var prepareStatusRow: some View {
        if isPreparingToSend, let prepareToSendStatus {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
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
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 20, height: 20)
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
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
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
}
