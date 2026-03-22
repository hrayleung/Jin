import SwiftUI

// MARK: - Response Metrics Popover

struct ResponseMetricsPopover: View {
    let metrics: ResponseMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            metricRow(title: "Input tokens", value: formattedTokens(metrics.usage?.inputTokens))
            metricRow(title: "Output tokens", value: formattedTokens(metrics.usage?.outputTokens))
            metricRow(title: "Time to first token", value: formattedSeconds(metrics.timeToFirstTokenSeconds))
            metricRow(title: "Duration", value: formattedSeconds(metrics.durationSeconds))
            metricRow(title: "Output speed", value: formattedSpeed(metrics.outputTokensPerSecond))
        }
        .padding(.vertical, JinSpacing.small)
        .padding(.horizontal, JinSpacing.medium)
        .frame(minWidth: 260, alignment: .leading)
    }

    @ViewBuilder
    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.large) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.callout)
    }

    private func formattedTokens(_ value: Int?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.grouping(.automatic))
    }

    private func formattedSeconds(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1fs", value)
    }

    private func formattedSpeed(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1fT/s", value)
    }
}

// MARK: - Chunked Text View

struct ChunkedTextView: View {
    let chunks: [String]
    let font: Font
    let allowsTextSelection: Bool

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            ForEach(chunks.indices, id: \.self) { idx in
                Text(verbatim: chunks[idx])
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if allowsTextSelection {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}

// MARK: - Load Earlier Messages

struct LoadEarlierMessagesRow: View {
    let hiddenCount: Int
    let pageSize: Int
    let onLoad: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button {
                onLoad()
            } label: {
                let count = min(pageSize, hiddenCount)
                Text("Load \(count) earlier messages (\(hiddenCount) hidden)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.vertical, 10)
    }
}
