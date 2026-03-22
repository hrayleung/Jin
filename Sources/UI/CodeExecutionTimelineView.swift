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
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .clipped()
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.spring(duration: 0.25, bounce: 0), value: isExpanded)
            .animation(.easeInOut(duration: 0.2), value: animationSignature)
            .onChange(of: isStreaming) { _, streaming in
                if streaming {
                    let mode = Self.resolveDisplayMode()
                    if mode.startsExpandedDuringStreaming {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded = true
                        }
                    }
                } else {
                    let mode = Self.resolveDisplayMode()
                    if mode == .collapseOnComplete {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
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
            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(headerTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isStreaming, hasActiveExecution {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                if let compactStatus = compactStatusStyle {
                    HStack(spacing: 4) {
                        Image(systemName: compactStatus.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(compactStatus.text)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(compactStatus.color)
                    .lineLimit(1)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
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
                    showsConnectorAbove: index > 0,
                    showsConnectorBelow: index < activities.count - 1
                )
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.xSmall)
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

    private var compactStatusStyle: (text: String, icon: String, color: Color)? {
        if hasActiveExecution {
            return nil
        }

        let failedCount = activities.filter { $0.status == .failed || $0.status == .incomplete }.count
        let completedCount = activities.filter { $0.status == .completed }.count

        if failedCount > 0 {
            let label: String
            if completedCount > 0 {
                label = "\(completedCount) ok / \(failedCount) failed"
            } else {
                label = failedCount == 1 ? "Failed" : "\(failedCount) failed"
            }
            return (
                text: label,
                icon: "xmark.circle",
                color: Color(nsColor: .systemOrange).opacity(0.95)
            )
        }
        if completedCount > 0 {
            return (
                text: "Done",
                icon: "checkmark.circle",
                color: Color(nsColor: .systemGreen).opacity(0.88)
            )
        }
        return nil
    }

    private var animationSignature: String {
        activities
            .map { "\($0.id):\($0.status)" }
            .joined(separator: "|")
    }
}
