import Foundation

/// "Windows 對照": the Windows equivalent of a Mac key combination, shown under
/// each keystroke pill so students on Windows can follow along.
///
/// Based on Apple's "Windows keyboard equivalents for Mac" guide
/// (https://support.apple.com/guide/mac-help/cpmh0038/mac):
/// Command ⌘ ↔ Ctrl (most shortcuts), Option ⌥ ↔ Alt, Delete ↔ Backspace,
/// fn-Delete ↔ Delete, Return ↔ Enter, Shift-Command-3/4/5 ↔ Print Screen /
/// Snipping, Option-Command-Esc ↔ Ctrl-Alt-Delete (Force Quit), plus the
/// common text-navigation and app shortcuts below.
enum WindowsEquivalent {
    /// Whole-combination translations where the generic key-by-key mapping
    /// would be wrong. Keys are Mac combos written as sorted modifier tokens
    /// plus the main key name (see `signature`).
    static let shortcuts: [String: String] = [
        "cmd+KeyQ": "Alt + F4",
        "cmd+Tab": "Alt + Tab",
        "cmd+shift+Tab": "Alt + Shift + Tab",
        "cmd+BackQuote": "Alt + Tab",
        "alt+cmd+Escape": "Ctrl + Alt + Delete",
        "cmd+shift+Num3": "Print Screen",
        "cmd+shift+Num4": "⊞ Win + Shift + S",
        "cmd+shift+Num5": "⊞ Win + Shift + S",
        "cmd+Space": "⊞ Win",
        "ctrl+cmd+KeyQ": "⊞ Win + L",
        "cmd+KeyM": "⊞ Win + ↓",
        "ctrl+cmd+KeyF": "F11",
        "cmd+shift+KeyZ": "Ctrl + Y",
        "cmd+LeftArrow": "Home",
        "cmd+RightArrow": "End",
        "cmd+UpArrow": "Ctrl + Home",
        "cmd+DownArrow": "Ctrl + End",
        "cmd+shift+LeftArrow": "Shift + Home",
        "cmd+shift+RightArrow": "Shift + End",
        "cmd+shift+UpArrow": "Ctrl + Shift + Home",
        "cmd+shift+DownArrow": "Ctrl + Shift + End",
        "alt+LeftArrow": "Ctrl + ←",
        "alt+RightArrow": "Ctrl + →",
        "alt+shift+LeftArrow": "Ctrl + Shift + ←",
        "alt+shift+RightArrow": "Ctrl + Shift + →",
        "alt+Backspace": "Ctrl + Backspace",
        "cmd+Backspace": "Delete",
        "fn+Backspace": "Delete",
        "cmd+Return": "Ctrl + Enter",
        "Return": "Enter",
        "Backspace": "Backspace",
        "Delete": "Delete",
        "cmd+alt+KeyD": "⊞ Win + D",
        "ctrl+Left": "Right-click",
        "cmd+Left": "Ctrl + Click",
        "alt+Left": "Alt + Click",
        "cmd+KeyH": "⊞ Win + ↓",
        "cmd+alt+Space": "⊞ Win + E",
        "cmd+KeyI": "Ctrl + I",
        "cmd+Comma": "Ctrl + ,",
        "ctrl+cmd+Space": "⊞ Win + .",
    ]

    private static func token(_ name: String) -> String? {
        switch name {
        case KeyName.metaLeft, KeyName.metaRight: return "cmd"
        case KeyName.alt: return "alt"
        case KeyName.controlLeft, KeyName.controlRight: return "ctrl"
        case KeyName.shiftLeft, KeyName.shiftRight: return "shift"
        case KeyName.function: return "fn"
        default: return nil
        }
    }

    private static func lookup(_ names: [String]) -> String? {
        let mods = Set(names.compactMap(token))
        let others = names.filter { token($0) == nil }
        // Accept any modifier order in the table.
        for (key, value) in shortcuts {
            let parts = key.split(separator: "+").map(String.init)
            let keyMods = Set(parts.filter { ["ctrl", "alt", "shift", "cmd", "fn"].contains($0) })
            let keyOthers = parts.filter { !["ctrl", "alt", "shift", "cmd", "fn"].contains($0) }
            if keyMods == mods && keyOthers == others {
                return value
            }
        }
        return nil
    }

    private static func windowsName(_ name: String) -> String {
        switch name {
        case KeyName.metaLeft, KeyName.metaRight: return "Ctrl"
        case KeyName.alt: return "Alt"
        case KeyName.controlLeft, KeyName.controlRight: return "Ctrl"
        case KeyName.shiftLeft, KeyName.shiftRight: return "Shift"
        case KeyName.function: return "Fn"
        case KeyName.capsLock: return "Caps Lock"
        case "Return": return "Enter"
        case "Backspace": return "Backspace"
        case "Delete": return "Delete"
        case "Escape": return "Esc"
        case "Space": return "Space"
        case "Tab": return "Tab"
        case "PageUp": return "Page Up"
        case "PageDown": return "Page Down"
        case "Home": return "Home"
        case "End": return "End"
        case "KpReturn": return "Enter"
        case KeyName.mouseLeft: return "Click"
        case KeyName.mouseRight: return "Right-click"
        case KeyName.mouseMiddle: return "Middle-click"
        case KeyName.drag: return "Drag"
        case KeyName.scrollUp, KeyName.scrollDown: return "Scroll"
        default:
            let display = KeyDisplayMap.display(for: name)
            switch display.category {
            case .arrow: return display.glyph ?? display.label
            case .letter, .digit, .punctuation, .function, .numpad: return display.label
            default: return display.label.capitalized
            }
        }
    }

    /// The Windows text for a combination, or nil when it would add nothing
    /// (plain letters and digits are the same on both systems).
    static func text(for names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        if let known = lookup(names) { return known }
        let hasModifier = names.contains { token($0) != nil }
        let hasSpecial = names.contains { ["Return", "Backspace", "Delete", "KpReturn"].contains($0) }
        guard hasModifier || hasSpecial else { return nil }
        // Command and Control both become Ctrl; avoid "Ctrl + Ctrl".
        var parts: [String] = []
        for name in KeyName.displayOrder(names) {
            let part = windowsName(name)
            if !parts.contains(part) { parts.append(part) }
        }
        // Windows writes modifiers as Ctrl, Alt, Shift.
        let rank = ["Ctrl": 0, "Alt": 1, "Shift": 2, "Fn": 3]
        let mods = parts.filter { rank[$0] != nil }.sorted { rank[$0]! < rank[$1]! }
        let rest = parts.filter { rank[$0] == nil }
        return (mods + rest).joined(separator: " + ")
    }
}
