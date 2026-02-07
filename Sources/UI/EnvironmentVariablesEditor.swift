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
                ForEach($pairs) { $pair in
                    HStack(spacing: 8) {
                        TextField("Key", text: $pair.key)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        if showValues {
                            TextField("Value", text: $pair.value)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Value", text: $pair.value)
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
