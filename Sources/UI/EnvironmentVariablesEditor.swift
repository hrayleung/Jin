import SwiftUI

struct EnvironmentVariablePair: Identifiable, Equatable, Sendable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

struct EnvironmentVariablesEditor: View {
    enum Kind {
        case environment
        case headers
    }

    @Binding var pairs: [EnvironmentVariablePair]
    var kind: Kind = .environment

    @State private var showValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            if pairs.isEmpty {
                Text(kind == .headers ? "No custom headers" : "No environment variables")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                // One grid owns both the headings and fields. Independent
                // HStacks can choose different column widths for secure fields.
                Grid(horizontalSpacing: JinSpacing.small, verticalSpacing: JinSpacing.small) {
                    GridRow {
                        columnHeading(kind == .headers ? "Header" : "Variable")
                        columnHeading("Value")
                        Color.clear.frame(width: 24, height: 1)
                    }

                    ForEach($pairs) { $pair in
                        GridRow {
                            JinSettingsTextField(text: $pair.key, usesMonospacedFont: true)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .accessibilityLabel(kind == .headers ? "Header name" : "Variable name")

                            Group {
                                if showValues {
                                    JinSettingsTextField(text: $pair.value, usesMonospacedFont: true)
                                } else {
                                    SecureField("", text: $pair.value)
                                        .labelsHidden()
                                        .multilineTextAlignment(.leading)
                                        .font(.system(.body, design: .monospaced))
                                        .jinSettingsTextFieldStyle(.roundedBorder)
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .accessibilityLabel("Value for \(pair.key.isEmpty ? "new entry" : pair.key)")

                            Button(role: .destructive) {
                                pairs.removeAll { $0.id == pair.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .help("Remove entry")
                            .accessibilityLabel("Remove \(pair.key.isEmpty ? "entry" : pair.key)")
                        }
                    }
                }
            }

            HStack(spacing: JinSpacing.medium) {
                Button {
                    pairs.append(EnvironmentVariablePair(key: "", value: ""))
                } label: {
                    Label(kind == .headers ? "Add header" : "Add variable", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .fixedSize()

                Spacer(minLength: JinSpacing.medium)

                if !pairs.isEmpty {
                    Button {
                        showValues.toggle()
                    } label: {
                        Label(showValues ? "Hide values" : "Show values", systemImage: showValues ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .accessibilityValue(showValues ? "Values visible" : "Values hidden")
                }
            }
            .font(.callout)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.jinSettingsFieldChrome, .roundedBorder)
    }

    private func columnHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
