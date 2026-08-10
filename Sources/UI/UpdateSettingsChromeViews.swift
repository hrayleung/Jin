import SwiftUI
import AppKit

// MARK: - Version Hero

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
        JinSettingsSection("Installed Version", style: .plain) {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                identityRow
                metadataRow
                checkActionRow

                if let checkError {
                    Text(checkError)
                        .jinInlineErrorText()
                }
            }
            .padding(JinSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jinSurface(.subtle, cornerRadius: JinRadius.large)
        }
    }

    private var identityRow: some View {
        HStack(alignment: .center, spacing: JinSpacing.large) {
            appIcon

            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text("Jin")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                    Text("v\(version)")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()

                    if let build, !build.isEmpty {
                        Text("·")
                            .foregroundStyle(JinSemanticColor.textTertiary)

                        Text("Build \(build)")
                            .font(.subheadline)
                            .foregroundStyle(JinSemanticColor.textSecondary)
                            .monospacedDigit()
                    }
                }

                channelBadge
            }

            Spacer(minLength: 0)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
        }
        .shadow(color: JinSemanticColor.shadowSubtle, radius: 8, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    private var channelBadge: some View {
        HStack(alignment: .center, spacing: 5) {
            Circle()
                .fill(allowPreRelease ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(allowPreRelease ? "Pre-release" : "Stable")
                .font(.caption.weight(.medium))
                .foregroundStyle(allowPreRelease ? Color.orange : JinSemanticColor.textSecondary)
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(
                    allowPreRelease
                        ? Color.orange.opacity(0.12)
                        : JinSemanticColor.subtleSurface
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    allowPreRelease
                        ? Color.orange.opacity(0.28)
                        : JinSemanticColor.borderSubtle,
                    lineWidth: JinStrokeWidth.hairline
                )
        }
        .padding(.top, 2)
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(JinSemanticColor.textTertiary)
                .frame(width: 14, height: 14, alignment: .center)

            Text(lastCheckSummary)
                .font(.caption)
                .foregroundStyle(JinSemanticColor.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var checkActionRow: some View {
        Button(action: onCheckForUpdates) {
            HStack(spacing: JinSpacing.small) {
                if sessionInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(sessionInProgress ? "Checking…" : "Check for Updates")
                    .fontWeight(.medium)
            }
            .frame(minWidth: 168)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canCheckForUpdates || sessionInProgress)
        .help(canCheckForUpdates ? "Check for a newer build" : "Update checks unavailable")
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
        parts.append(allowPreRelease ? "pre-release" : "stable")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Automatic Updates

struct UpdateSettingsAutomaticSection: View {
    @Binding var isOn: Bool

    var body: some View {
        JinSettingsSection("Automatic Updates") {
            UpdateSettingsPreferenceRow(
                title: "Check on launch",
                systemImage: "arrow.triangle.2.circlepath.circle",
                isOn: $isOn
            )
        }
    }
}

// MARK: - Channel

struct UpdateSettingsChannelSection: View {
    @Binding var allowPreRelease: Bool

    var body: some View {
        JinSettingsSection("Release Channel") {
            UpdateSettingsPreferenceRow(
                title: "Include pre-release versions",
                systemImage: "flask",
                isOn: $allowPreRelease
            )

            if allowPreRelease {
                Text("Pre-release builds may be unstable.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, JinSpacing.xSmall)
            }
        }
    }
}

// MARK: - Shared Preference Row

struct UpdateSettingsPreferenceRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(JinSemanticColor.accentSurface)
                )
                .accessibilityHidden(true)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: JinSpacing.medium)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
