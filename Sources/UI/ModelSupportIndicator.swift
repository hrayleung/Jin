import SwiftUI

/// A secondary status mark that leaves the model name as the visual anchor.
struct ModelSupportIndicator: View {
    var body: some View {
        Image(systemName: "checkmark.seal")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("Fully supported by Jin")
            .accessibilityLabel("Fully supported by Jin")
    }
}
