import AppKit
import Foundation

struct KeyShortcut: Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    static func == (lhs: KeyShortcut, rhs: KeyShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    static let defaultPushToTalk = KeyShortcut(
        keyCode: 63, // Fn / Globe — shared with Compare and Wispr Flow
        modifiers: []
    )

    static let optionPushToTalk = KeyShortcut(
        keyCode: 58,
        modifiers: []
    )

    static let controlSpace = KeyShortcut(
        keyCode: 49,
        modifiers: [.control]
    )

    static let defaultCommandMode = KeyShortcut(
        keyCode: 8, // C
        modifiers: [.command, .control]
    )

    var displayString: String {
        if modifiers.isEmpty, Self.optionKeyCodes.contains(keyCode) {
            return "⌥"
        }
        if modifiers.isEmpty, keyCode == 63 {
            return "Fn"
        }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    var isOptionOnly: Bool {
        modifiers.isEmpty && Self.optionKeyCodes.contains(keyCode)
    }

    static let optionKeyCodes: Set<UInt16> = [58, 61]
    static let controlKeyCodes: Set<UInt16> = [59, 62]
    static let shiftKeyCodes: Set<UInt16> = [56, 60]
    static let commandKeyCodes: Set<UInt16> = [54, 55]

    func encode() -> Data? {
        let payload = CodableShortcut(
            keyCode: keyCode,
            modifierRaw: modifiers.rawValue
        )
        return try? JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data?) -> KeyShortcut? {
        guard let data,
              let payload = try? JSONDecoder().decode(CodableShortcut.self, from: data)
        else { return nil }
        return KeyShortcut(
            keyCode: payload.keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: payload.modifierRaw)
        )
    }

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard matchesKeyCode(keyCode) else { return false }
        let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let eventMods = Self.nsModifiers(from: flags).intersection(relevant)
        return eventMods == modifiers.intersection(relevant)
    }

    func matchesKeyCode(_ keyCode: Int64) -> Bool {
        Self.equivalentKeyCodes(for: self.keyCode).contains(UInt16(keyCode))
    }

    static func equivalentKeyCodes(for keyCode: UInt16) -> Set<UInt16> {
        if optionKeyCodes.contains(keyCode) { return optionKeyCodes }
        if controlKeyCodes.contains(keyCode) { return controlKeyCodes }
        if shiftKeyCodes.contains(keyCode) { return shiftKeyCodes }
        if commandKeyCodes.contains(keyCode) { return commandKeyCodes }
        return [keyCode]
    }

    static func nsModifiers(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        case 53: return "Esc"
        case 58: return "⌥"
        case 61: return "⌥"
        case 59: return "⌃"
        case 55: return "⌘"
        case 56: return "⇧"
        case 63: return "Fn"
        default: return "Key\(keyCode)"
        }
    }

    /// Common reserved shortcuts that must not be bound.
    static let reservedConflicts: [KeyShortcut] = [
        KeyShortcut(keyCode: 12, modifiers: [.command]), // Cmd+Q
        KeyShortcut(keyCode: 13, modifiers: [.command]), // Cmd+W
        KeyShortcut(keyCode: 48, modifiers: [.command]), // Cmd+Tab (keyCode may vary)
        KeyShortcut(keyCode: 53, modifiers: [.command]), // Cmd+Esc
        KeyShortcut(keyCode: 96, modifiers: []), // F5 — often system
    ]

    func conflictsWithSystem() -> String? {
        if Self.reservedConflicts.contains(self) {
            return "This shortcut conflicts with a system reserved binding."
        }
        // Require a modifier OR a standalone modifier/fn-style key for safety.
        let isModifierOnlyKey = [55, 56, 58, 59, 60, 61, 62, 63].contains(keyCode)
        if modifiers.isEmpty && !isModifierOnlyKey {
            return "Shortcut must include a modifier key (⌃ ⌥ ⇧ ⌘) or be a modifier key itself."
        }
        return nil
    }
}

private struct CodableShortcut: Codable {
    var keyCode: UInt16
    var modifierRaw: UInt
}
