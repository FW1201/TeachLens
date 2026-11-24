import Foundation

// Key names and display data, ported from Keyviz
// (Legacy/keyviz/src/types/event.ts and src/lib/keymaps.ts, © Rahul Mula,
// GPL-3.0), keeping only the macOS labels. The names match Keyviz's so that
// exported filter lists stay compatible. Foundation only.

enum KeyName {
    static let shiftLeft = "ShiftLeft"
    static let shiftRight = "ShiftRight"
    static let controlLeft = "ControlLeft"
    static let controlRight = "ControlRight"
    static let alt = "Alt"
    static let metaLeft = "MetaLeft"
    static let metaRight = "MetaRight"
    static let capsLock = "CapsLock"
    static let function = "Function"

    // Mouse actions shown as keys
    static let mouseLeft = "Left"
    static let mouseRight = "Right"
    static let mouseMiddle = "Middle"
    static let mouseBack = "Back"
    static let mouseForward = "Forward"
    static let drag = "Drag"
    static let scrollUp = "ScrollUp"
    static let scrollDown = "ScrollDown"

    static let modifiers: Set<String> = [
        shiftLeft, shiftRight, controlLeft, controlRight, alt, metaLeft, metaRight, function
    ]

    /// macOS order for modifier glyphs: ⌃ ⌥ ⇧ ⌘ (then fn).
    static func modifierRank(_ name: String) -> Int? {
        switch name {
        case controlLeft, controlRight: return 0
        case alt: return 1
        case shiftLeft, shiftRight: return 2
        case metaLeft, metaRight: return 3
        case function: return 4
        default: return nil
        }
    }

    /// Modifiers first in macOS order, then the remaining keys in press order.
    static func displayOrder(_ names: [String]) -> [String] {
        let modifiers = names
            .enumerated()
            .compactMap { item -> (Int, Int, String)? in
                guard let rank = modifierRank(item.element) else { return nil }
                return (rank, item.offset, item.element)
            }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map(\.2)
        let others = names.filter { modifierRank($0) == nil }
        return modifiers + others
    }
}

enum KeyCategory: String, Sendable {
    case modifier, letter, digit, punctuation, function, arrow, navigation, special, numpad, mouse, other
}

/// How a key is drawn: text, an optional glyph (⌘), an optional shifted
/// symbol (@ over 2) and an optional SF Symbol name.
struct KeyDisplay: Equatable, Sendable {
    var label: String
    var shortLabel: String?
    var glyph: String?
    var symbol: String?
    var sfSymbol: String?
    var category: KeyCategory

    init(_ label: String, short: String? = nil, glyph: String? = nil, symbol: String? = nil,
         sf: String? = nil, _ category: KeyCategory) {
        self.label = label
        self.shortLabel = short
        self.glyph = glyph
        self.symbol = symbol
        self.sfSymbol = sf
        self.category = category
    }

    var isModifier: Bool { category == .modifier }
    var compactLabel: String { shortLabel ?? label }
}

enum KeyDisplayMap {
    static func display(for name: String) -> KeyDisplay {
        if let known = table[name] { return known }
        if name.hasPrefix("Key"), name.count == 4 {
            return KeyDisplay(String(name.suffix(1)), .letter)
        }
        if name.hasPrefix("F"), Int(name.dropFirst()) != nil {
            return KeyDisplay(name, .function)
        }
        return KeyDisplay(name.lowercased(), .other)
    }

    private static let digitSymbols: [String: String] = [
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")"
    ]

    static let table: [String: KeyDisplay] = {
        var map: [String: KeyDisplay] = [
            // Modifiers
            KeyName.controlLeft: KeyDisplay("control", short: "ctrl", glyph: "⌃", .modifier),
            KeyName.controlRight: KeyDisplay("control", short: "ctrl", glyph: "⌃", .modifier),
            KeyName.alt: KeyDisplay("option", short: "opt", glyph: "⌥", .modifier),
            KeyName.shiftLeft: KeyDisplay("shift", glyph: "⇧", .modifier),
            KeyName.shiftRight: KeyDisplay("shift", glyph: "⇧", .modifier),
            KeyName.metaLeft: KeyDisplay("command", short: "cmd", glyph: "⌘", .modifier),
            KeyName.metaRight: KeyDisplay("command", short: "cmd", glyph: "⌘", .modifier),
            KeyName.function: KeyDisplay("fn", glyph: "fn", sf: "globe", .modifier),
            KeyName.capsLock: KeyDisplay("caps lock", short: "caps", glyph: "⇪", .special),
            // Editing / control
            "Backspace": KeyDisplay("delete", short: "del", glyph: "⌫", .special),
            "Delete": KeyDisplay("forward delete", short: "del", glyph: "⌦", .special),
            "Tab": KeyDisplay("tab", glyph: "⇥", .special),
            "Space": KeyDisplay("space", glyph: "␣", .special),
            "Return": KeyDisplay("return", glyph: "↩", .special),
            "Escape": KeyDisplay("escape", short: "esc", glyph: "⎋", .special),
            "Help": KeyDisplay("help", .special),
            // Navigation
            "Home": KeyDisplay("home", glyph: "↖", .navigation),
            "End": KeyDisplay("end", glyph: "↘", .navigation),
            "PageUp": KeyDisplay("page up", short: "pg up", glyph: "⇞", .navigation),
            "PageDown": KeyDisplay("page down", short: "pg dn", glyph: "⇟", .navigation),
            "UpArrow": KeyDisplay("up", glyph: "↑", .arrow),
            "DownArrow": KeyDisplay("down", glyph: "↓", .arrow),
            "LeftArrow": KeyDisplay("left", glyph: "←", .arrow),
            "RightArrow": KeyDisplay("right", glyph: "→", .arrow),
            // Punctuation
            "BackQuote": KeyDisplay("`", symbol: "~", .punctuation),
            "Minus": KeyDisplay("-", symbol: "_", .punctuation),
            "Equal": KeyDisplay("=", symbol: "+", .punctuation),
            "LeftBracket": KeyDisplay("[", symbol: "{", .punctuation),
            "RightBracket": KeyDisplay("]", symbol: "}", .punctuation),
            "BackSlash": KeyDisplay("\\", symbol: "|", .punctuation),
            "SemiColon": KeyDisplay(";", symbol: ":", .punctuation),
            "Quote": KeyDisplay("'", symbol: "\"", .punctuation),
            "Comma": KeyDisplay(",", symbol: "<", .punctuation),
            "Dot": KeyDisplay(".", symbol: ">", .punctuation),
            "Slash": KeyDisplay("/", symbol: "?", .punctuation),
            "IntlBackslash": KeyDisplay("§", symbol: "±", .punctuation),
            // Numpad
            "KpDivide": KeyDisplay("/", .numpad),
            "KpMultiply": KeyDisplay("*", .numpad),
            "KpMinus": KeyDisplay("-", .numpad),
            "KpPlus": KeyDisplay("+", .numpad),
            "KpEqual": KeyDisplay("=", .numpad),
            "KpDecimal": KeyDisplay(".", .numpad),
            "KpClear": KeyDisplay("clear", glyph: "⌧", .numpad),
            "KpReturn": KeyDisplay("enter", glyph: "⌤", .numpad),
            // Media
            "VolumeUp": KeyDisplay("volume up", short: "vol +", sf: "speaker.wave.3.fill", .special),
            "VolumeDown": KeyDisplay("volume down", short: "vol -", sf: "speaker.wave.1.fill", .special),
            "VolumeMute": KeyDisplay("mute", sf: "speaker.slash.fill", .special),
            // Input sources (JIS)
            "Eisu": KeyDisplay("英数", .special),
            "Kana": KeyDisplay("かな", .special),
            // Mouse
            KeyName.mouseLeft: KeyDisplay("left click", short: "click", sf: "computermouse.fill", .mouse),
            KeyName.mouseRight: KeyDisplay("right click", short: "right", sf: "computermouse.fill", .mouse),
            KeyName.mouseMiddle: KeyDisplay("middle click", short: "middle", sf: "computermouse.fill", .mouse),
            KeyName.mouseBack: KeyDisplay("mouse back", short: "back", sf: "chevron.left.circle", .mouse),
            KeyName.mouseForward: KeyDisplay("mouse forward", short: "forward", sf: "chevron.right.circle", .mouse),
            KeyName.drag: KeyDisplay("drag", sf: "hand.draw", .mouse),
            KeyName.scrollUp: KeyDisplay("scroll up", short: "scroll", sf: "arrow.up.circle", .mouse),
            KeyName.scrollDown: KeyDisplay("scroll down", short: "scroll", sf: "arrow.down.circle", .mouse),
        ]
        for digit in 0...9 {
            let d = String(digit)
            map["Num\(d)"] = KeyDisplay(d, symbol: digitSymbols[d], .digit)
            map["Kp\(d)"] = KeyDisplay(d, .numpad)
        }
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            map["Key\(letter)"] = KeyDisplay(String(letter), .letter)
        }
        for f in 1...20 {
            map["F\(f)"] = KeyDisplay("F\(f)", .function)
        }
        return map
    }()
}
