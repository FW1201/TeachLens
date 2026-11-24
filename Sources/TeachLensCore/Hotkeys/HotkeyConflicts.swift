import AppKit
import Carbon.HIToolbox

/// Lists every global shortcut TeachLens registers (including the Shift /
/// Option variants HotkeyService derives from a base shortcut) so a new
/// shortcut can be checked against them.
enum HotkeyConflicts {
    struct Shortcut: Equatable {
        var name: String
        var keyCode: Int
        var modifiers: UInt
    }

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static func normalized(_ modifiers: UInt) -> UInt {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(relevantModifiers).rawValue
    }

    static func registeredShortcuts(app: AppSettings) -> [Shortcut] {
        let shift = NSEvent.ModifierFlags.shift.rawValue
        let option = NSEvent.ModifierFlags.option.rawValue
        var list: [Shortcut] = [
            Shortcut(name: "Static Zoom", keyCode: app.hotKeyCode, modifiers: app.hotKeyModifiers),
            Shortcut(name: "Draw", keyCode: app.drawHotKeyCode, modifiers: app.drawHotKeyModifiers),
            Shortcut(name: "Live Zoom", keyCode: app.liveHotKeyCode, modifiers: app.liveHotKeyModifiers),
            Shortcut(name: "Break Timer", keyCode: app.breakHotKeyCode, modifiers: app.breakHotKeyModifiers),
            Shortcut(name: "Snip", keyCode: app.snipHotKeyCode, modifiers: app.snipHotKeyModifiers),
            Shortcut(name: "Snip to File", keyCode: app.snipHotKeyCode, modifiers: app.snipHotKeyModifiers ^ shift),
            Shortcut(name: "OCR Snip", keyCode: app.snipOcrHotKeyCode, modifiers: app.snipOcrHotKeyModifiers),
            Shortcut(name: "Record Screen", keyCode: app.recordHotKeyCode, modifiers: app.recordHotKeyModifiers),
            Shortcut(name: "Record Region", keyCode: app.recordHotKeyCode, modifiers: app.recordHotKeyModifiers ^ shift),
            Shortcut(name: "Panorama", keyCode: app.panoramaHotKeyCode, modifiers: app.panoramaHotKeyModifiers),
            Shortcut(name: "Panorama to File", keyCode: app.panoramaHotKeyCode, modifiers: app.panoramaHotKeyModifiers ^ shift),
            Shortcut(name: "DemoMirror", keyCode: app.demoMirrorHotKeyCode, modifiers: app.demoMirrorHotKeyModifiers),
            Shortcut(name: "DemoMirror Region", keyCode: app.demoMirrorHotKeyCode, modifiers: app.demoMirrorHotKeyModifiers ^ shift),
            Shortcut(name: "DemoMirror Window", keyCode: app.demoMirrorHotKeyCode, modifiers: app.demoMirrorHotKeyModifiers ^ option),
        ]
        #if !TEACHLENS_APP_STORE
        list.append(Shortcut(name: "DemoType", keyCode: app.demoTypeHotKeyCode, modifiers: app.demoTypeHotKeyModifiers))
        list.append(Shortcut(name: "DemoType Reset", keyCode: app.demoTypeHotKeyCode, modifiers: app.demoTypeHotKeyModifiers ^ shift))
        #endif
        let keystrokes = KeystrokeSettingsStore().load()
        list.append(Shortcut(name: "Show Keystrokes", keyCode: keystrokes.toggleKeyCode, modifiers: keystrokes.toggleModifiers))
        let spotlight = SpotlightSettingsStore().load()
        list.append(Shortcut(name: "Spotlight", keyCode: spotlight.toggleKeyCode, modifiers: spotlight.toggleModifiers))
        // A key code of 0 disables a shortcut.
        return list.filter { $0.keyCode != 0 }
    }

    /// The name of the existing shortcut that `keyCode` + `modifiers` would
    /// collide with, or nil when it is free.
    static func conflict(keyCode: Int, modifiers: UInt, app: AppSettings, ignoring own: String? = nil) -> String? {
        guard keyCode != 0 else { return nil }
        let wanted = normalized(modifiers)
        return registeredShortcuts(app: app).first {
            $0.name != own && $0.keyCode == keyCode && normalized($0.modifiers) == wanted
        }?.name
    }

    /// A readable form such as "⌃0".
    static func displayString(keyCode: Int, modifiers: UInt) -> String {
        guard keyCode != 0 else { return "Off" }
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        if let name = KeyCodeMap.name(for: keyCode) {
            let display = KeyDisplayMap.display(for: name)
            text += display.glyph ?? display.label.uppercased()
        } else {
            text += "#\(keyCode)"
        }
        return text
    }
}
