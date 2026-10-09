import SwiftUI

/// A secondary scope menu in the trailing edge of the search row.
struct ModelPickerScopeControl: View {
    @Binding var selection: ModelPickerScope

    var body: some View {
        Menu {
            Picker("Model filter", selection: $selection) {
                ForEach(ModelPickerScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(selection.rawValue)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .controlSize(.small)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(height: 26)
        .fixedSize()
        .help("Filter models")
        .accessibilityLabel("Model filter")
        .accessibilityValue(selection.rawValue)
    }
}
