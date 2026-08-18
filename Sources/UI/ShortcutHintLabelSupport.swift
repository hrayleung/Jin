import Foundation

enum ShortcutHintLabelSupport {
    /// Compact keycap text for the currently held modifiers.
    ///
    /// Held modifiers that are part of the binding are omitted (`⌘N` while
    /// holding ⌘ becomes `N`). Bindings that are not a superset of the held
    /// set return `nil` so they can disappear as the user adds Shift / Option.
    static func compactLabel(
        for binding: AppShortcutBinding?,
        heldModifiers: AppShortcutModifiers
    ) -> String? {
        guard let binding else { return nil }
        guard binding.modifiers.isSuperset(of: heldModifiers) else { return nil }
        let remaining = binding.modifiers.subtracting(heldModifiers)
        return remaining.displaySymbols + binding.key.displayText
    }

    static func helpText(_ title: String, binding: AppShortcutBinding?) -> String {
        guard let binding else { return title }
        return "\(title) (\(binding.displayLabel))"
    }
}
