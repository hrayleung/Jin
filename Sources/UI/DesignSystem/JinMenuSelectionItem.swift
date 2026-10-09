import SwiftUI

/// A menu choice whose checkmark belongs to the native menu's state column.
/// Image opacity is ignored when SwiftUI translates a label into an NSMenuItem.
struct JinMenuSelectionItem: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { isSelected },
            // Selecting the current choice still runs its action; it must not
            // turn a mutually exclusive selection off.
            set: { _ in action() }
        ))
        .toggleStyle(.automatic)
    }
}
