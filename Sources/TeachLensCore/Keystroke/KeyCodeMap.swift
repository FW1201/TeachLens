import Carbon.HIToolbox
import CoreGraphics

/// Maps macOS virtual key codes (kVK_*) to Keyviz-compatible key names.
enum KeyCodeMap {
    static func name(for keyCode: Int) -> String? {
        table[keyCode]
    }

    static let table: [Int: String] = {
        var map: [Int: String] = [
            kVK_ANSI_A: "KeyA", kVK_ANSI_B: "KeyB", kVK_ANSI_C: "KeyC", kVK_ANSI_D: "KeyD",
            kVK_ANSI_E: "KeyE", kVK_ANSI_F: "KeyF", kVK_ANSI_G: "KeyG", kVK_ANSI_H: "KeyH",
            kVK_ANSI_I: "KeyI", kVK_ANSI_J: "KeyJ", kVK_ANSI_K: "KeyK", kVK_ANSI_L: "KeyL",
            kVK_ANSI_M: "KeyM", kVK_ANSI_N: "KeyN", kVK_ANSI_O: "KeyO", kVK_ANSI_P: "KeyP",
            kVK_ANSI_Q: "KeyQ", kVK_ANSI_R: "KeyR", kVK_ANSI_S: "KeyS", kVK_ANSI_T: "KeyT",
            kVK_ANSI_U: "KeyU", kVK_ANSI_V: "KeyV", kVK_ANSI_W: "KeyW", kVK_ANSI_X: "KeyX",
            kVK_ANSI_Y: "KeyY", kVK_ANSI_Z: "KeyZ",
            kVK_ANSI_1: "Num1", kVK_ANSI_2: "Num2", kVK_ANSI_3: "Num3", kVK_ANSI_4: "Num4",
            kVK_ANSI_5: "Num5", kVK_ANSI_6: "Num6", kVK_ANSI_7: "Num7", kVK_ANSI_8: "Num8",
            kVK_ANSI_9: "Num9", kVK_ANSI_0: "Num0",
            kVK_ANSI_Grave: "BackQuote", kVK_ANSI_Minus: "Minus", kVK_ANSI_Equal: "Equal",
            kVK_ANSI_LeftBracket: "LeftBracket", kVK_ANSI_RightBracket: "RightBracket",
            kVK_ANSI_Backslash: "BackSlash", kVK_ANSI_Semicolon: "SemiColon", kVK_ANSI_Quote: "Quote",
            kVK_ANSI_Comma: "Comma", kVK_ANSI_Period: "Dot", kVK_ANSI_Slash: "Slash",
            kVK_ISO_Section: "IntlBackslash",
            kVK_Return: "Return", kVK_Tab: "Tab", kVK_Space: "Space", kVK_Delete: "Backspace",
            kVK_Escape: "Escape", kVK_ForwardDelete: "Delete", kVK_Help: "Help",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PageUp", kVK_PageDown: "PageDown",
            kVK_LeftArrow: "LeftArrow", kVK_RightArrow: "RightArrow",
            kVK_UpArrow: "UpArrow", kVK_DownArrow: "DownArrow",
            kVK_Shift: KeyName.shiftLeft, kVK_RightShift: KeyName.shiftRight,
            kVK_Control: KeyName.controlLeft, kVK_RightControl: KeyName.controlRight,
            kVK_Option: KeyName.alt, kVK_RightOption: KeyName.alt,
            kVK_Command: KeyName.metaLeft, kVK_RightCommand: KeyName.metaRight,
            kVK_CapsLock: KeyName.capsLock, kVK_Function: KeyName.function,
            kVK_ANSI_Keypad0: "Kp0", kVK_ANSI_Keypad1: "Kp1", kVK_ANSI_Keypad2: "Kp2",
            kVK_ANSI_Keypad3: "Kp3", kVK_ANSI_Keypad4: "Kp4", kVK_ANSI_Keypad5: "Kp5",
            kVK_ANSI_Keypad6: "Kp6", kVK_ANSI_Keypad7: "Kp7", kVK_ANSI_Keypad8: "Kp8",
            kVK_ANSI_Keypad9: "Kp9", kVK_ANSI_KeypadDecimal: "KpDecimal",
            kVK_ANSI_KeypadMultiply: "KpMultiply", kVK_ANSI_KeypadPlus: "KpPlus",
            kVK_ANSI_KeypadMinus: "KpMinus", kVK_ANSI_KeypadDivide: "KpDivide",
            kVK_ANSI_KeypadEquals: "KpEqual", kVK_ANSI_KeypadEnter: "KpReturn",
            kVK_ANSI_KeypadClear: "KpClear",
            kVK_VolumeUp: "VolumeUp", kVK_VolumeDown: "VolumeDown", kVK_Mute: "VolumeMute",
            kVK_JIS_Eisu: "Eisu", kVK_JIS_Kana: "Kana",
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        for (index, code) in functionKeys.enumerated() {
            map[code] = "F\(index + 1)"
        }
        return map
    }()

    // Device-dependent modifier bits (IOKit NX_DEVICE*KEYMASK). They tell left
    // and right modifiers apart, which the generic CGEventFlags cannot.
    private static let deviceLeftControl: UInt64 = 0x0000_0001
    private static let deviceLeftShift: UInt64 = 0x0000_0002
    private static let deviceRightShift: UInt64 = 0x0000_0004
    private static let deviceLeftCommand: UInt64 = 0x0000_0008
    private static let deviceRightCommand: UInt64 = 0x0000_0010
    private static let deviceLeftOption: UInt64 = 0x0000_0020
    private static let deviceRightOption: UInt64 = 0x0000_0040
    private static let deviceRightControl: UInt64 = 0x0000_2000

    /// For a `flagsChanged` event, whether the modifier with `keyCode` is now
    /// down. Returns nil for keys that are not tracked as held modifiers
    /// (Caps Lock toggles, so it is reported as a tap instead).
    static func isModifierDown(keyCode: Int, flags: UInt64) -> Bool? {
        let generic = CGEventFlags(rawValue: flags)
        switch keyCode {
        case kVK_Shift: return flags & deviceLeftShift != 0
        case kVK_RightShift: return flags & deviceRightShift != 0
        case kVK_Control: return flags & deviceLeftControl != 0
        case kVK_RightControl: return flags & deviceRightControl != 0
        case kVK_Command: return flags & deviceLeftCommand != 0
        case kVK_RightCommand: return flags & deviceRightCommand != 0
        case kVK_Option: return flags & deviceLeftOption != 0
        case kVK_RightOption: return flags & deviceRightOption != 0
        case kVK_Function: return generic.contains(.maskSecondaryFn)
        default: return nil
        }
    }
}
