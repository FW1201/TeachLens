import AppKit
import SwiftUI

/// Settings ▸ 字幕 / Captions.
struct CaptionSettingsPane: View {
    let controller: CaptionController
    @State private var draft = CaptionSettings()
    @State private var running = false
    @State private var didLoad = false
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        Form {
            Section {
                Toggle(L10n.t("Live captions", "即時字幕"), isOn: $running)
                Picker(L10n.t("Language", "語言"), selection: $draft.localeIdentifier) {
                    ForEach(CaptionSettings.languages, id: \.id) { Text($0.title).tag($0.id) }
                }
                LabeledContent(L10n.t("Text size", "字級")) {
                    HStack {
                        Slider(value: $draft.fontSize, in: 16...72, step: 2).frame(width: 180)
                        Text("\(Int(draft.fontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Picker(L10n.t("Position", "位置"), selection: $draft.atTop) {
                    Text(L10n.t("Bottom", "下方")).tag(false)
                    Text(L10n.t("Top", "上方")).tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent(L10n.t("Shortcut", "快捷鍵")) {
                    Button(recorder.isRecording ? L10n.t("Press a shortcut…", "請按快捷鍵…")
                           : HotkeyConflicts.displayString(keyCode: draft.toggleKeyCode, modifiers: draft.toggleModifiers)) {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start { draft.toggleKeyCode = $0; draft.toggleModifiers = $1 }
                        }
                    }
                }
                Text(L10n.t("Recognition runs on this Mac when the language supports it. Check names and terms before publishing.",
                            "支援的語言會在這台 Mac 上辨識。發佈前請校對人名與專有名詞。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("Transcript", "逐字稿")) {
                HStack {
                    Button { controller.exportSRT() } label: { Label(".srt", systemImage: "captions.bubble") }
                    Button { controller.exportVTT() } label: { Label(".vtt", systemImage: "globe") }
                    Button { controller.exportTXT() } label: { Label(".txt", systemImage: "doc.plaintext") }
                    Spacer()
                    Button(role: .destructive) { controller.clearTranscript() } label: { Label(L10n.t("Clear", "清除"), systemImage: "trash") }
                }
                Button {
                    controller.exportLastRecording()
                } label: {
                    Label(L10n.t("Export captions for the last recording (.srt)", "匯出上一段錄影的字幕（.srt）"),
                          systemImage: "record.circle")
                }
                .disabled(controller.lastRecording == nil)
                Text(L10n.t("You choose where each file is saved; TeachLens then offers to show it in Finder.",
                            "每次匯出都會讓你選擇存放位置，存好後可直接在 Finder 中顯示。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            if !didLoad {
                draft = controller.settings
                running = controller.isRunning
                didLoad = true
            }
        }
        .onDisappear { recorder.stop() }
        .onChange(of: draft) { _, value in
            guard didLoad else { return }
            controller.update { $0 = value }
        }
        .onChange(of: running) { _, value in
            guard didLoad else { return }
            controller.setEnabled(value)
        }
    }
}

/// Settings ▸ 課程模式 / Course Modes.
struct CourseModeSettingsPane: View {
    let controller: CourseModeController
    @State private var refresh = 0

    var body: some View {
        Form {
            Section(L10n.t("Modes", "模式")) {
                ForEach(controller.allModes) { mode in
                    HStack {
                        Image(systemName: mode.symbol).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.name)
                            Text(summary(mode)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if mode.id == controller.currentModeID {
                            Text(L10n.t("In use", "使用中")).font(.caption).foregroundStyle(.green)
                        }
                        Button {
                            controller.apply(mode)
                            refresh += 1
                        } label: {
                            Label(L10n.t("Apply", "套用"), systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            .id(refresh)
            Section {
                HStack {
                    Button { controller.saveCurrent(); refresh += 1 } label: { Label(L10n.t("Save current setup…", "存成新模式…"), systemImage: "plus.square.on.square") }
                    Button { controller.importModes(); refresh += 1 } label: { Label(L10n.t("Import…", "匯入…"), systemImage: "square.and.arrow.down") }
                    Button { controller.exportModes() } label: { Label(L10n.t("Export…", "匯出…"), systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button(role: .destructive) { controller.removeCustomModes(); refresh += 1 } label: { Label(L10n.t("Remove custom", "移除自訂"), systemImage: "trash") }
                        .disabled(controller.customModes.isEmpty)
                }
                Text(L10n.t("Restoring a mode at launch never turns on the microphone or the break timer.",
                            "重開 TeachLens 時會回到上次的模式，但不會自動開麥克風或計時器。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func summary(_ mode: CourseMode) -> String {
        var parts: [String] = []
        if mode.keystrokes {
            parts.append(mode.keystrokeFilter == .none ? L10n.t("every key", "每個鍵") : L10n.t("shortcuts", "快捷鍵"))
        }
        if mode.spotlight { parts.append(L10n.t("spotlight", "聚光燈")) }
        if mode.cursorHighlight { parts.append(L10n.t("cursor ring", "游標光圈")) }
        if mode.captions { parts.append(L10n.t("captions", "字幕")) }
        if mode.startBreakTimer { parts.append(L10n.t("break timer", "休息計時")) }
        return parts.isEmpty ? L10n.t("everything off", "全部關閉") : parts.joined(separator: " · ")
    }
}

/// Settings ▸ 白板 / Whiteboard.
struct WhiteboardSettingsPane: View {
    let controller: WhiteboardController

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.t("Shortcut", "快捷鍵"), value: "⌃⇧W")
                LabeledContent(L10n.t("Pages", "頁數"), value: "\(controller.pageCount)")
                Button { controller.show() } label: { Label(L10n.t("Open whiteboard", "打開白板"), systemImage: "rectangle.and.pencil.and.ellipsis") }
            }
            Section(L10n.t("Export", "匯出")) {
                HStack {
                    Button { controller.exportPDF() } label: { Label(L10n.t("All pages as PDF…", "全部頁面存成 PDF…"), systemImage: "doc.richtext") }
                    Button { controller.exportPNG() } label: { Label(L10n.t("Current page as PNG…", "本頁存成 PNG…"), systemImage: "photo") }
                }
                LabeledContent(L10n.t("Auto-saved to", "自動保存位置")) {
                    Button(controller.saveLocation.deletingLastPathComponent().lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([controller.saveLocation])
                    }
                    .buttonStyle(.link)
                }
                Text(L10n.t("Keys in the whiteboard: P pen · H highlighter · E eraser · ← → pages · ⌘Z undo.",
                            "白板中的按鍵：P 畫筆 · H 螢光筆 · E 橡皮擦 · ← → 換頁 · ⌘Z 復原。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
