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
    @Binding var pairs: [EnvironmentVariablePair]

    @State private var showValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pairs.isEmpty {
                Text("No environment variables")
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("KEY")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("VALUE")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Color.clear.frame(width: 20)
                    }

                    ForEach($pairs) { $pair in
                        GridRow {
                            TextField("", text: $pair.key)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 180, idealWidth: 220)

                            if showValues {
                                TextField("", text: $pair.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("", text: $pair.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(role: .destructive) {
                                pairs.removeAll { $0.id == pair.id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                }
            }

            HStack {
                Button {
                    pairs.append(EnvironmentVariablePair(key: "", value: ""))
                } label: {
                    Label("Add variable", systemImage: "plus")
                }

                Spacer()

                Toggle("Show values", isOn: $showValues)
                    .toggleStyle(.switch)
            }
        }
    }
}
