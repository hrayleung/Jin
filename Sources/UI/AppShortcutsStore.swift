import SwiftUI

struct AppShortcutAssignmentResult {
    let reassignedFrom: AppShortcutAction?
}

@MainActor
final class AppShortcutsStore: ObservableObject {
    static let shared = AppShortcutsStore()

    @Published private(set) var customBindings: [AppShortcutAction: AppShortcutBinding] = [:]
    @Published private(set) var disabledActions: Set<AppShortcutAction> = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func binding(for action: AppShortcutAction) -> AppShortcutBinding? {
        guard !disabledActions.contains(action) else { return nil }
        if let custom = customBindings[action] { return custom }
        return action.defaultBinding
    }

    func keyboardShortcut(for action: AppShortcutAction) -> KeyboardShortcut? {
        binding(for: action)?.keyboardShortcut
    }

    func displayLabel(for action: AppShortcutAction) -> String {
        binding(for: action)?.displayLabel ?? "None"
    }

    func isCustomized(_ action: AppShortcutAction) -> Bool {
        customBindings[action] != nil || disabledActions.contains(action)
    }

    func restoreDefault(for action: AppShortcutAction) {
        customBindings.removeValue(forKey: action)
        disabledActions.remove(action)
        persist()
    }

    func resetAllToDefaults() {
        customBindings.removeAll()
        disabledActions.removeAll()
        persist()
    }

    @discardableResult
    func setBinding(_ binding: AppShortcutBinding?, for action: AppShortcutAction) -> AppShortcutAssignmentResult {
        var reassigned: AppShortcutAction?

        if let binding {
            if let conflictedAction = AppShortcutAction.allCases.first(where: { candidate in
                candidate != action && self.binding(for: candidate) == binding
            }) {
                customBindings.removeValue(forKey: conflictedAction)
                disabledActions.insert(conflictedAction)
                reassigned = conflictedAction
            }

            disabledActions.remove(action)
            if binding == action.defaultBinding {
                customBindings.removeValue(forKey: action)
            } else {
                customBindings[action] = binding
            }
        } else {
            customBindings.removeValue(forKey: action)
            disabledActions.insert(action)
        }

        persist()
        return AppShortcutAssignmentResult(reassignedFrom: reassigned)
    }

    private func load() {
        guard let data = defaults.data(forKey: AppPreferenceKeys.keyboardShortcuts),
              let state = try? JSONDecoder().decode(PersistedShortcutState.self, from: data) else {
            return
        }

        customBindings = Dictionary(uniqueKeysWithValues: state.customBindings.compactMap { pair in
            guard let action = AppShortcutAction(rawValue: pair.key) else { return nil }
            return (action, pair.value)
        })

        disabledActions = Set(state.disabledActionIDs.compactMap(AppShortcutAction.init(rawValue:)))
        normalizeConflictsIfNeeded()
    }

    private func persist() {
        let state = PersistedShortcutState(
            customBindings: Dictionary(uniqueKeysWithValues: customBindings.map { ($0.key.rawValue, $0.value) }),
            disabledActionIDs: disabledActions.map(\.rawValue).sorted()
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: AppPreferenceKeys.keyboardShortcuts)
    }

    private func normalizeConflictsIfNeeded() {
        struct ResolvedBinding {
            let action: AppShortcutAction
            let isCustom: Bool
        }

        var used: [AppShortcutBinding: ResolvedBinding] = [:]
        var needsPersist = false

        for action in AppShortcutAction.allCases {
            guard let binding = binding(for: action) else { continue }
            let current = ResolvedBinding(action: action, isCustom: customBindings[action] != nil)

            guard let existing = used[binding] else {
                used[binding] = current
                continue
            }

            if current.isCustom && !existing.isCustom {
                customBindings.removeValue(forKey: existing.action)
                disabledActions.insert(existing.action)
                used[binding] = current
            } else {
                customBindings.removeValue(forKey: action)
                disabledActions.insert(action)
            }
            needsPersist = true
        }

        if needsPersist {
            persist()
        }
    }

    private struct PersistedShortcutState: Codable {
        var customBindings: [String: AppShortcutBinding]
        var disabledActionIDs: [String]
    }
}
