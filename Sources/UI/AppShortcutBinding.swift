import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AppShortcutBinding: Codable, Hashable {
    var key: AppShortcutKey
    var modifiers: AppShortcutModifiers

    static func command(_ key: String, modifiers: AppShortcutModifiers = [.command]) -> AppShortcutBinding {
        let normalized = key.trimmedLowercased
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

private extension CharacterSet {
    static let printableASCII = CharacterSet(charactersIn: " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
}
