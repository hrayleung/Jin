import SwiftUI
import AppKit

/// Displays a timeline of code execution activities from provider-native code execution tools
/// (OpenAI Code Interpreter, Anthropic Code Execution, xAI Code Interpreter).
struct CodeExecutionTimelineView: View {
    let activities: [CodeExecutionActivity]
    let isStreaming: Bool

    @State private var isExpanded: Bool

    init(activities: [CodeExecutionActivity], isStreaming: Bool) {
        self.activities = activities
        self.isStreaming = isStreaming
        let mode = Self.resolveDisplayMode()
        if isStreaming {
            _isExpanded = State(initialValue: mode.startsExpandedDuringStreaming)
        } else {
            _isExpanded = State(initialValue: mode.startsExpandedOnComplete)
        }
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                headerRow

                VStack(spacing: 0) {
                    if isExpanded {
                        expandedContent
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .clipped()
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.spring(duration: 0.3, bounce: 0.05), value: isExpanded)
            .animation(.easeInOut(duration: 0.25), value: animationSignature)
            .onChange(of: isStreaming) { _, streaming in
                if streaming {
                    let mode = Self.resolveDisplayMode()
                    if mode.startsExpandedDuringStreaming {
                        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                            isExpanded = true
                        }
                    }
                } else {
                    let mode = Self.resolveDisplayMode()
                    if mode == .collapseOnComplete {
                        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                            isExpanded = false
                        }
                    }
                }
            }
        }
    }

    private static func resolveDisplayMode() -> CodeExecutionDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.codeExecutionDisplayMode) ?? ""
        return CodeExecutionDisplayMode(rawValue: raw) ?? .expanded
    }

    // MARK: - Header Row

    private var headerRow: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)

                Text(headerTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isStreaming, hasActiveExecution {
                    CodeExecActivityIndicator()
                }

                if let badge = statusBadge {
                    CodeExecCompactStatusBadge(style: badge)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(duration: 0.25, bounce: 0.15), value: isExpanded)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                CodeExecutionEntryView(
                    activity: activity,
                    entryIndex: index,
                    isStreaming: isStreaming
                )
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.small)
    }

    // MARK: - Computed

    private var hasActiveExecution: Bool {
        activities.contains { activity in
            switch activity.status {
            case .inProgress, .writingCode, .interpreting:
                return true
            default:
                return false
            }
        }
    }

    private var headerTitle: String {
        if activities.count == 1 {
            return "Code Execution"
        }
        return "\(activities.count) Code Executions"
    }

    private var statusBadge: CodeExecCompactStatusStyle? {
        if hasActiveExecution {
            let activeActivity = activities.first {
                $0.status == .interpreting || $0.status == .writingCode || $0.status == .inProgress
            }
            let statusText: String
            switch activeActivity?.status {
            case .writingCode:
                statusText = "Writing code..."
            case .interpreting:
                statusText = "Running..."
            default:
                statusText = "In progress..."
            }
            return CodeExecCompactStatusStyle(text: statusText, icon: "play.circle.fill", color: .accentColor)
        }

        let failedCount = activities.filter { $0.status == .failed }.count
        let completedCount = activities.filter { $0.status == .completed }.count

        if failedCount > 0 {
            return CodeExecCompactStatusStyle(text: "Failed", icon: "xmark.circle.fill", color: Color(nsColor: .systemOrange))
        }
        if completedCount > 0 {
            return CodeExecCompactStatusStyle(text: "Done", icon: "checkmark.circle.fill", color: .secondary)
        }
        return nil
    }

    private var animationSignature: String {
        activities
            .map { "\($0.id):\($0.status)" }
            .joined(separator: "|")
    }
}

// MARK: - Compact Status Style

private struct CodeExecCompactStatusStyle {
    let text: String
    let icon: String
    let color: Color
}

// MARK: - Compact Status Badge

private struct CodeExecCompactStatusBadge: View {
    let style: CodeExecCompactStatusStyle

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(style.text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(style.color.opacity(0.9))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(style.color.opacity(0.1))
        )
        .lineLimit(1)
    }
}

// MARK: - Activity Indicator (3-dot wave)

private struct CodeExecActivityIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: isAnimating ? -2.5 : 2.5)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .frame(height: 10)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Code Execution Entry

private struct CodeExecutionEntryView: View {
    let activity: CodeExecutionActivity
    let entryIndex: Int
    let isStreaming: Bool

    @State private var isCodeExpanded = false
    @State private var isOutputExpanded = true
    @State private var hasAppeared = false
    @State private var isRunningPulse = false

    private var executionStatus: CodeExecVisualStatus {
        switch activity.status {
        case .inProgress, .writingCode, .interpreting:
            return .running
        case .completed:
            return .success
        case .failed, .incomplete:
            return .error
        case .unknown:
            return .running
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entryHeader
            entryBody
        }
        .jinSurface(.neutral, cornerRadius: JinRadius.small)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 6)
        .onAppear {
            isRunningPulse = executionStatus == .running
            withAnimation(.spring(duration: 0.4, bounce: 0.08).delay(Double(entryIndex) * 0.06)) {
                hasAppeared = true
            }
        }
        .onChange(of: executionStatus) { _, newValue in
            isRunningPulse = newValue == .running
        }
    }

    // MARK: - Entry Header

    private var entryHeader: some View {
        HStack(spacing: JinSpacing.small) {
            statusDot

            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            statusPill
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
    }

    @ViewBuilder
    private var statusDot: some View {
        let style = visualStyle
        ZStack {
            if executionStatus == .running {
                Circle()
                    .fill(style.accent.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(isRunningPulse ? 1.6 : 1.0)
                    .opacity(isRunningPulse ? 0.0 : 0.5)
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isRunningPulse
                    )
            }

            Circle()
                .fill(style.accent)
                .frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let style = visualStyle

        HStack(spacing: 4) {
            if executionStatus == .running {
                Circle()
                    .fill(style.accent)
                    .frame(width: 4, height: 4)
            } else {
                Image(systemName: executionStatus == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            }

            Text(statusLabel)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(style.text)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(style.accent.opacity(0.1))
        )
        .lineLimit(1)
    }

    private var statusLabel: String {
        switch activity.status {
        case .inProgress: return "Starting..."
        case .writingCode: return "Writing..."
        case .interpreting: return "Running..."
        case .completed: return "Done"
        case .failed: return "Failed"
        case .incomplete: return "Incomplete"
        case .unknown: return "Running..."
        }
    }

    // MARK: - Entry Body

    @ViewBuilder
    private var entryBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let code = activity.code, !code.isEmpty {
                codeSection(code)
            }

            if let stdout = activity.stdout, !stdout.isEmpty {
                outputSection(title: "Output", text: stdout, isError: false)
            }

            if let stderr = activity.stderr, !stderr.isEmpty {
                outputSection(title: "Error", text: stderr, isError: true)
            }

            if activity.code == nil, activity.stdout == nil {
                statusPlaceholder
            }
        }
    }

    // MARK: - Code Section

    @ViewBuilder
    private func codeSection(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.5)

            HStack(spacing: JinSpacing.small) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Text("Code")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                CodeExecCopyButton(text: code)

                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                        isCodeExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCodeExpanded ? 90 : 0))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(JinIconButtonStyle())
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.xSmall)

            if isCodeExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                        .textSelection(.enabled)
                        .padding(.horizontal, JinSpacing.medium)
                        .padding(.bottom, JinSpacing.small)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.1), value: isCodeExpanded)
    }

    // MARK: - Output Section

    @ViewBuilder
    private func outputSection(title: String, text: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.5)

            HStack(spacing: JinSpacing.small) {
                Image(systemName: isError ? "exclamationmark.triangle" : "text.alignleft")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isError ? Color(nsColor: .systemOrange).opacity(0.8) : Color.secondary.opacity(0.6))

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isError ? Color(nsColor: .systemOrange).opacity(0.9) : .secondary)

                Spacer(minLength: 0)

                CodeExecCopyButton(text: text)
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.xSmall)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isError ? Color(nsColor: .systemOrange).opacity(0.9) : .primary.opacity(0.85))
                    .textSelection(.enabled)
                    .lineLimit(20)
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.bottom, JinSpacing.small)
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

                Text(activity.status == .writingCode ? "Writing code..." : activity.status == .interpreting ? "Running code..." : "Starting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
        }
    }

    // MARK: - Visual Style

    private var visualStyle: CodeExecVisualStyle {
        switch executionStatus {
        case .running:
            return CodeExecVisualStyle(
                accent: Color.accentColor.opacity(0.7),
                text: .secondary
            )
        case .success:
            return CodeExecVisualStyle(
                accent: Color.secondary.opacity(0.7),
                text: .secondary
            )
        case .error:
            return CodeExecVisualStyle(
                accent: Color(nsColor: .systemOrange).opacity(0.95),
                text: Color(nsColor: .systemOrange).opacity(0.95)
            )
        }
    }
}

// MARK: - Visual Types

private enum CodeExecVisualStatus: Equatable {
    case running
    case success
    case error
}

private struct CodeExecVisualStyle {
    let accent: Color
    let text: Color
}

// MARK: - Copy Button with Animation

private struct CodeExecCopyButton: View {
    let text: String

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            copyToPasteboard()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(didCopy ? Color.accentColor : .secondary)
                .frame(width: 20, height: 20)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(JinIconButtonStyle())
        .disabled(text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) == nil)
    }

    @MainActor
    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) {
            didCopy = true
        }

        resetTask?.cancel()
        resetTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                didCopy = false
            }
        }
    }
}
