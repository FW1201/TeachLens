import AppKit
import SwiftUI

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

// MARK: - Handout

extension WindowsEquivalent {
    /// The handout rows: Mac shortcut, Windows shortcut, what it does.
    static var cheatSheet: [(mac: String, windows: String, meaning: String)] {
        [
            ("⌘C", "Ctrl + C", L10n.t("Copy", "複製")),
            ("⌘X", "Ctrl + X", L10n.t("Cut", "剪下")),
            ("⌘V", "Ctrl + V", L10n.t("Paste", "貼上")),
            ("⌘Z", "Ctrl + Z", L10n.t("Undo", "復原")),
            ("⇧⌘Z", "Ctrl + Y", L10n.t("Redo", "重做")),
            ("⌘A", "Ctrl + A", L10n.t("Select all", "全選")),
            ("⌘S", "Ctrl + S", L10n.t("Save", "儲存")),
            ("⌘F", "Ctrl + F", L10n.t("Find", "尋找")),
            ("⌘P", "Ctrl + P", L10n.t("Print", "列印")),
            ("⌘T", "Ctrl + T", L10n.t("New tab", "新分頁")),
            ("⌘W", "Ctrl + W", L10n.t("Close tab or window", "關閉分頁或視窗")),
            ("⌘Q", "Alt + F4", L10n.t("Quit the app", "結束應用程式")),
            ("⌘Tab", "Alt + Tab", L10n.t("Switch apps", "切換應用程式")),
            ("⌘Space", "⊞ Win", L10n.t("Search", "搜尋")),
            ("⇧⌘3", "Print Screen", L10n.t("Screenshot", "全螢幕截圖")),
            ("⇧⌘4", "⊞ Win + Shift + S", L10n.t("Screenshot a region", "區域截圖")),
            ("⌥⌘Esc", "Ctrl + Alt + Delete", L10n.t("Force quit", "強制結束")),
            ("⌘←  ⌘→", "Home  End", L10n.t("Start / end of line", "移到行首／行尾")),
            ("⌥←  ⌥→", "Ctrl + ←  Ctrl + →", L10n.t("Previous / next word", "上一個／下一個字")),
            ("⌃ Click", "Right-click", L10n.t("Context menu", "右鍵選單")),
            ("Delete", "Backspace", L10n.t("Delete backward", "向左刪除")),
            ("fn + Delete", "Delete", L10n.t("Delete forward", "向右刪除")),
        ]
    }

    /// Saves the handout as a one-page A4 PDF.
    @MainActor
    static func exportCheatSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = L10n.t("Mac and Windows shortcuts.pdf", "Mac 與 Windows 快捷鍵對照.pdf")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let renderer = ImageRenderer(content: CheatSheetView(rows: cheatSheet).frame(width: 595, height: 842))
        var written = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            written = true
        }
        if written {
            ExportFeedback.saved(url)
        } else {
            ExportFeedback.failed(CocoaError(.fileWriteUnknown))
        }
    }
}

/// The printable handout (light, black-on-white for printing).
private struct CheatSheetView: View {
    let rows: [(mac: String, windows: String, meaning: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("Mac ↔ Windows shortcuts", "Mac ↔ Windows 快捷鍵對照"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(L10n.t("Suggested equivalents; the actual shortcut depends on the app.",
                        "建議對照，實際快捷鍵依軟體而異。"))
                .font(.system(size: 10)).foregroundStyle(.gray)
                .padding(.bottom, 14)
            HStack {
                Text(L10n.t("What it does", "功能")).frame(width: 170, alignment: .leading)
                Text("Mac").frame(width: 150, alignment: .leading)
                Text("Windows").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.gray)
            .padding(.vertical, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.meaning).frame(width: 170, alignment: .leading)
                    Text(row.mac).font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 150, alignment: .leading)
                    Text(row.windows).font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
                .padding(.vertical, 7)
                .padding(.horizontal, 6)
                .background(index.isMultiple(of: 2) ? Color.gray.opacity(0.08) : Color.clear)
            }
            Spacer()
            Text("TeachLens")
                .font(.system(size: 9)).foregroundStyle(.gray)
        }
        .foregroundStyle(.black)
        .padding(44)
        .background(Color.white)
    }
}
