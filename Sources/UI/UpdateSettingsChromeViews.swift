import SwiftUI
import AppKit

// MARK: - Installed Version

struct UpdateSettingsVersionHero: View {
    let version: String
    let build: String?
    let allowPreRelease: Bool
    let lastCheckDate: Date?
    let canCheckForUpdates: Bool
    let sessionInProgress: Bool
    let checkError: String?
    let onCheckForUpdates: () -> Void

    var body: some View {
        JinSettingsSection("Installed Version") {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                HStack(alignment: .center, spacing: JinSpacing.medium) {
                    identity
                    Spacer(minLength: JinSpacing.medium)
                    checkControl
                }

                if let checkError {
                    JinSettingsStatusText(text: checkError, isError: true)
                }
            }
            .padding(.vertical, JinSpacing.xSmall)
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            appIcon

            VStack(alignment: .leading, spacing: 2) {
                Text("Jin \(version)")
                    .font(.headline)
                    .monospacedDigit()

                Text(detailSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityIdentityLabel)
    }

    private var appIcon: some View {
        Group {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var checkControl: some View {
        if sessionInProgress {
            HStack(spacing: JinSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("Check for Updates", action: onCheckForUpdates)
                .disabled(!canCheckForUpdates)
                .help(canCheckForUpdates ? "Check for a newer version" : "Update checks are unavailable")
        }
    }

    private var detailSummary: String {
        var parts: [String] = []
        if let build, !build.isEmpty {
            parts.append("Build \(build)")
        }
        parts.append(lastCheckSummary)
        return parts.joined(separator: " · ")
    }

    private var lastCheckSummary: String {
        guard let lastCheckDate else {
            return "Not checked yet"
        }
        return "Last checked \(UpdateSettingsFormatting.relativeTimestamp(lastCheckDate))"
    }

    private var accessibilityIdentityLabel: String {
        var parts = ["Jin version \(version)"]
        if let build, !build.isEmpty {
            parts.append("build \(build)")
        }
        parts.append(allowPreRelease ? "pre-release channel" : "stable channel")
        parts.append(lastCheckSummary)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preferences

struct UpdateSettingsPreferencesSection: View {
    @Binding var automaticallyChecks: Bool
    @Binding var allowPreRelease: Bool

    var body: some View {
        JinSettingsSection("Preferences") {
            JinSettingsToggleRow("Check for updates on launch", isOn: $automaticallyChecks)
            JinSettingsToggleRow(
                "Include pre-release versions",
                supportingText: "Pre-release builds arrive sooner and may be unstable.",
                isOn: $allowPreRelease
            )
        }
    }
}

// MARK: - Formatting

enum UpdateSettingsFormatting {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func relativeTimestamp(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if abs(seconds) < 60 * 60 * 24 * 7 {
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        return absoluteFormatter.string(from: date)
    }
}
