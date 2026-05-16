import SwiftUI
import AppKit

// MARK: - Code Execution Entry

struct CodeExecutionEntryView: View {
    let activity: CodeExecutionActivity
    let entryIndex: Int
    let showsConnectorAbove: Bool
    let showsConnectorBelow: Bool

    @State private var isRunningPulse = false

    private var executionStatus: CodeExecVisualStatus {
        CodeExecutionEntrySupport.visualStatus(for: activity.status)
    }

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            ToolTimelinePresentationSupport.TerminalTimelineRail(
                glyph: executionStatus.timelineNodeGlyph,
                style: visualStyle,
                showsConnectorAbove: showsConnectorAbove,
                showsConnectorBelow: showsConnectorBelow,
                isRunningPulse: isRunningPulse
            )

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                entryHeader
                entryBody
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .jinSurface(.subtle, cornerRadius: JinRadius.small)
        }
        .animation(.spring(duration: 0.25, bounce: 0), value: executionStatus)
        .onAppear {
            updatePulseAnimation(for: executionStatus)
        }
        .onChange(of: executionStatus) { _, newValue in
            updatePulseAnimation(for: newValue)
        }
    }

    // MARK: - Entry Header

    private var entryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
            Image(systemName: "terminal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(visualStyle.accent)
                .frame(width: 16, height: 16)

            Text("Execution \(entryIndex + 1)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let returnCode = activity.returnCode, shouldShowReturnCode {
                Text("exit \(returnCode)")
                    .jinTagStyle(
                        foreground: returnCode == 0
                            ? .secondary
                            : ToolTimelinePresentationSupport.StatusTone.failure.emphasizedColor
                    )
            }

            statusPill
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let style = visualStyle

        ToolTimelinePresentationSupport.InlineStatusLabel(
            glyph: executionStatus.timelineNodeGlyph,
            label: statusLabel,
            textColor: style.text,
            accentColor: style.accent
        )
    }

    private var statusLabel: String {
        CodeExecutionEntrySupport.statusLabel(for: activity.status)
    }

    // MARK: - Entry Body

    @ViewBuilder
    private var entryBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            if let code = activity.code, !code.isEmpty {
                CodeExecContentBlockView(
                    title: "Generated Code",
                    text: code,
                    style: .code,
                    badgeText: codeBadgeText,
                    language: codeLanguage
                )
            }

            if let containerID = activity.containerID, !containerID.isEmpty {
                metadataBlock(
                    title: "Container",
                    value: containerID,
                    copyHelpText: "Copy container ID"
                )
            }

            if let stdout = activity.stdout, !stdout.isEmpty {
                CodeExecContentBlockView(
                    title: "Output",
                    text: stdout,
                    style: .output
                )
            }

            if let stderr = activity.stderr, !stderr.isEmpty {
                CodeExecContentBlockView(
                    title: "Error",
                    text: stderr,
                    style: .error
                )
            }

            if let outputImages = activity.outputImages, !outputImages.isEmpty {
                Text(CodeExecutionEntrySupport.imageOutputSummary(count: outputImages.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.vertical, JinSpacing.small)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
            }

            if let outputFiles = activity.outputFiles, !outputFiles.isEmpty {
                outputFilesBlock(outputFiles)
            }

            if !hasDisplayableContent {
                statusPlaceholder
            }
        }
    }

    // MARK: - Status Placeholder

    @ViewBuilder
    private var statusPlaceholder: some View {
        if executionStatus == .running {
            HStack(spacing: JinSpacing.small) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)

                Text(CodeExecutionEntrySupport.statusPlaceholderText(for: activity.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .jinSurface(.subtle, cornerRadius: JinRadius.small)
        }
    }

    // MARK: - Visual Style

    private var visualStyle: ToolTimelinePresentationSupport.StatusVisualStyle {
        switch executionStatus {
        case .running:
            return ToolTimelinePresentationSupport.terminalStatusStyle(for: .running)
        case .success:
            return ToolTimelinePresentationSupport.terminalStatusStyle(for: .success)
        case .error:
            return ToolTimelinePresentationSupport.terminalStatusStyle(for: .error)
        case .neutral:
            return ToolTimelinePresentationSupport.neutralStatusStyle()
        }
    }

    private var hasDisplayableContent: Bool {
        CodeExecutionEntrySupport.hasDisplayableContent(activity)
    }

    private var shouldShowReturnCode: Bool {
        CodeExecutionEntrySupport.shouldShowReturnCode(for: activity.status)
    }

    private var codeLanguage: CodeExecCodeLanguage? {
        CodeExecutionEntrySupport.codeLanguage(for: activity)
    }

    private var codeBadgeText: String? {
        CodeExecutionEntrySupport.codeBadgeText(for: codeLanguage)
    }

    private func updatePulseAnimation(for status: CodeExecVisualStatus) {
        isRunningPulse = status == .running
    }

    @ViewBuilder
    private func metadataBlock(title: String, value: String, copyHelpText: String) -> some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)

            Spacer(minLength: 0)

            CopyToPasteboardButton(
                text: value,
                helpText: copyHelpText,
                useProminentStyle: false
            )
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }

    @ViewBuilder
    private func outputFilesBlock(_ outputFiles: [CodeExecutionOutputFile]) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(CodeExecutionEntrySupport.fileOutputSummary(count: outputFiles.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(outputFiles, id: \.self) { outputFile in
                metadataBlock(
                    title: "File ID",
                    value: outputFile.id,
                    copyHelpText: "Copy file ID"
                )
            }
        }
    }
}

// MARK: - Visual Types

enum CodeExecVisualStatus: Equatable {
    case running
    case success
    case error
    case neutral

    var timelineNodeGlyph: ToolTimelinePresentationSupport.TerminalStatusNodeGlyph {
        switch self {
        case .running:
            return .running
        case .success:
            return .success
        case .error:
            return .error
        case .neutral:
            return .neutral
        }
    }
}
