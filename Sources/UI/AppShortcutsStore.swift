import SwiftUI
#if os(macOS)
import AppKit
#endif

enum AppShortcutSection: String, CaseIterable {
    case workspace
    case composer
    case conversation

    var title: String {
        rawValue.capitalized
    }

    var subtitle: String {
        switch self {
        case .workspace:
            return "Window and sidebar navigation."
        case .composer:
            return "Drafting and sending controls."
        case .conversation:
            return "Actions for the selected chat."
        }
    }
}

enum AppShortcutAction: String, CaseIterable, Identifiable {
    case toggleChatList
    case searchChats
    case newChat
    case newAssistant
    case openAssistantSettings

    case focusComposer
    case openModelPicker
    case attachFiles
    case expandComposer
    case stopGenerating

    case renameChat
    case toggleStarChat
    case deleteChat

    var id: String { rawValue }

    var section: AppShortcutSection {
        switch self {
        case .toggleChatList, .searchChats, .newChat, .newAssistant, .openAssistantSettings:
            return .workspace
        case .focusComposer, .openModelPicker, .attachFiles, .expandComposer, .stopGenerating:
            return .composer
        case .renameChat, .toggleStarChat, .deleteChat:
            return .conversation
        }
    }

    var title: String {
        switch self {
        case .toggleChatList:
            return "Toggle Chat List"
        case .searchChats:
            return "Search Chats"
        case .newChat:
            return "New Chat"
        case .newAssistant:
            return "New Assistant"
        case .openAssistantSettings:
            return "Assistant Settings"
        case .focusComposer:
            return "Focus Composer"
        case .openModelPicker:
            return "Open Model Picker"
        case .attachFiles:
            return "Attach Files"
        case .expandComposer:
            return "Expand Composer"
        case .stopGenerating:
            return "Stop Generating"
        case .renameChat:
            return "Rename Selected Chat"
        case .toggleStarChat:
            return "Star / Unstar Chat"
        case .deleteChat:
            return "Delete Selected Chat"
        }
    }

    var subtitle: String {
        switch self {
        case .toggleChatList:
            return "Show or hide the left chat sidebar."
        case .searchChats:
            return "Jump to the chat search field."
        case .newChat:
            return "Create a new conversation."
        case .newAssistant:
            return "Create a new assistant profile."
        case .openAssistantSettings:
            return "Open the assistant inspector."
        case .focusComposer:
            return "Move focus to the message composer."
        case .openModelPicker:
            return "Open model and provider selection."
        case .attachFiles:
            return "Add files to the current draft."
        case .expandComposer:
            return "Open the full-size composer."
        case .stopGenerating:
            return "Stop current generation (same as macOS cancel)."
        case .renameChat:
            return "Rename the currently selected chat."
        case .toggleStarChat:
            return "Mark or unmark the selected chat as starred."
        case .deleteChat:
            return "Delete the selected chat."
        }
    }

    var defaultBinding: AppShortcutBinding? {
        switch self {
        case .toggleChatList:
            return .command("b")
        case .searchChats:
            return .command("f")
        case .newChat:
            return .command("n")
        case .newAssistant:
            return .command("n", modifiers: [.shift, .command])
        case .openAssistantSettings:
            return .command("i")
        case .focusComposer:
            return .command("k")
        case .openModelPicker:
            return .command("m", modifiers: [.shift, .command])
        case .attachFiles:
            return .command("a", modifiers: [.shift, .command])
        case .expandComposer:
            return .command("e", modifiers: [.shift, .command])
        case .stopGenerating:
            return .command(".")
        case .renameChat:
            return .command("r", modifiers: [.shift, .command])
        case .toggleStarChat:
            return .command("s", modifiers: [.shift, .command])
        case .deleteChat:
            return AppShortcutBinding(key: .delete, modifiers: [.command])
        }
    }
}

struct AppShortcutBinding: Codable, Hashable {
    var key: AppShortcutKey
    var modifiers: AppShortcutModifiers

    static func command(_ key: String, modifiers: AppShortcutModifiers = [.command]) -> AppShortcutBinding {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let first = normalized.first.map(String.init) ?? "k"
        return AppShortcutBinding(key: .character(first), modifiers: modifiers)
    }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(key.keyEquivalent, modifiers: modifiers.eventModifiers)
    }

    var displayLabel: String {
        modifiers.displaySymbols + key.displayText
    }
}

enum AppShortcutKey: Hashable {
    case character(String)
    case delete
    case forwardDelete
    case escape
    case returnKey
    case tab
    case space
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow

    private static let specialKeyTokens: [(String, AppShortcutKey)] = [
        ("delete", .delete), ("forwardDelete", .forwardDelete), ("escape", .escape),
        ("return", .returnKey), ("tab", .tab), ("space", .space),
        ("upArrow", .upArrow), ("downArrow", .downArrow),
        ("leftArrow", .leftArrow), ("rightArrow", .rightArrow)
    ]

    private static let tokenToKey: [String: AppShortcutKey] = Dictionary(
        uniqueKeysWithValues: specialKeyTokens
    )

    fileprivate init?(token: String) {
        if token.hasPrefix("char:"),
           let value = token.split(separator: ":", maxSplits: 1).last,
           value.count == 1 {
            self = .character(String(value))
            return
        }

        guard let mapped = Self.tokenToKey[token] else { return nil }
        self = mapped
    }

    fileprivate var token: String {
        if case .character(let value) = self {
            return "char:\(value.lowercased())"
        }

        return Self.specialKeyTokens.first(where: { $0.1 == self })?.0 ?? "unknown"
    }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .character(let value):
            return KeyEquivalent(Character(value.lowercased()))
        case .delete:
            return .delete
        case .forwardDelete:
            return .deleteForward
        case .escape:
            return .escape
        case .returnKey:
            return .return
        case .tab:
            return .tab
        case .space:
            return .space
        case .upArrow:
            return .upArrow
        case .downArrow:
            return .downArrow
        case .leftArrow:
            return .leftArrow
        case .rightArrow:
            return .rightArrow
        }
    }

    var displayText: String {
        switch self {
        case .character(let value):
            return value.uppercased()
        case .delete:
            return "⌫"
        case .forwardDelete:
            return "⌦"
        case .escape:
            return "⎋"
        case .returnKey:
            return "↩"
        case .tab:
            return "⇥"
        case .space:
            return "Space"
        case .upArrow:
            return "↑"
        case .downArrow:
            return "↓"
        case .leftArrow:
            return "←"
        case .rightArrow:
            return "→"
        }
    }

    #if os(macOS)
    private static let keyCodeMap: [UInt16: AppShortcutKey] = [
        51: .delete, 117: .forwardDelete, 53: .escape, 36: .returnKey,
        48: .tab, 49: .space, 126: .upArrow, 125: .downArrow,
        123: .leftArrow, 124: .rightArrow
    ]

    init?(event: NSEvent) {
        if let mapped = Self.keyCodeMap[event.keyCode] {
            self = mapped
            return
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              chars.count == 1,
              let scalar = chars.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              CharacterSet.printableASCII.contains(scalar) else {
            return nil
        }

        self = .character(String(chars))
    }
    #endif
}

extension AppShortcutKey: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let token = try container.decode(String.self)
        guard let value = AppShortcutKey(token: token) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid shortcut key token: \(token)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }
}

struct AppShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = AppShortcutModifiers(rawValue: 1 << 0)
    static let shift = AppShortcutModifiers(rawValue: 1 << 1)
    static let option = AppShortcutModifiers(rawValue: 1 << 2)
    static let control = AppShortcutModifiers(rawValue: 1 << 3)

    private static let swiftUIMapping: [(AppShortcutModifiers, EventModifiers)] = [
        (.command, .command), (.shift, .shift), (.option, .option), (.control, .control)
    ]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventModifiers: EventModifiers) {
        self = Self.swiftUIMapping.reduce(into: []) { result, pair in
            if eventModifiers.contains(pair.1) { result.insert(pair.0) }
        }
    }

    #if os(macOS)
    private static let nsEventMapping: [(AppShortcutModifiers, NSEvent.ModifierFlags)] = [
        (.command, .command), (.shift, .shift), (.option, .option), (.control, .control)
    ]

    init(eventFlags: NSEvent.ModifierFlags) {
        self = Self.nsEventMapping.reduce(into: []) { result, pair in
            if eventFlags.contains(pair.1) { result.insert(pair.0) }
        }
    }
    #endif

    var eventModifiers: EventModifiers {
        Self.swiftUIMapping.reduce(into: EventModifiers()) { result, pair in
            if contains(pair.0) { result.insert(pair.1) }
        }
    }

    /// Standard macOS display order: Control, Option, Shift, Command.
    var displaySymbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }
            .map(\.1)
            .joined()
    }

    var includesCommandKey: Bool {
        contains(.command)
    }
}

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
        var used: [AppShortcutBinding: AppShortcutAction] = [:]
        var needsPersist = false

        for action in AppShortcutAction.allCases {
            guard let binding = binding(for: action) else { continue }
            if used[binding] == nil {
                used[binding] = action
                continue
            }

            customBindings.removeValue(forKey: action)
            disabledActions.insert(action)
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

private extension CharacterSet {
    static let printableASCII = CharacterSet(charactersIn: " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
}
