import SwiftUI
import AppKit

// MARK: - Code Execution Entry

struct CodeExecutionEntryView: View {
    let activity: CodeExecutionActivity
    let entryIndex: Int
    var showsHeader: Bool = false

    private var executionStatus: CodeExecVisualStatus {
        CodeExecutionEntrySupport.visualStatus(for: activity.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            if showsHeader {
                entryHeader
            }
            entryBody
        }
        .animation(.easeInOut(duration: 0.18), value: executionStatus)
    }

    // MARK: - Entry Header (multi-execution only)

    private var entryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
            Text("Execution \(entryIndex + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JinSemanticColor.textSecondary)
                .lineLimit(1)

            quietStatus

            if let returnCode = activity.returnCode, shouldShowReturnCode {
                Text("exit \(returnCode)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(
                        returnCode == 0
                            ? JinSemanticColor.textTertiary
                            : ToolTimelinePresentationSupport.StatusTone.failure.emphasizedColor
                    )
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var quietStatus: some View {
        let style = visualStyle
        HStack(spacing: 4) {
            if executionStatus != .running {
                Image(systemName: executionStatus.statusGlyph)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.accent)
            }

            if executionStatus != .success {
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.text)
            }
        }
        .lineLimit(1)
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
                    title: codeBadgeText ?? "Code",
                    text: code,
                    style: .code,
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
            Text(CodeExecutionEntrySupport.statusPlaceholderText(for: activity.status))
                .font(.caption)
                .foregroundStyle(.secondary)
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

    var statusGlyph: String {
        switch self {
        case .running:
            return "circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .neutral:
            return "circle"
        }
    }
}
