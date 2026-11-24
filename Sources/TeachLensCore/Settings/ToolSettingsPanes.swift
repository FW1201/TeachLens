import AppKit
import SwiftUI

/// Each global shortcut set in the tool panes.
enum ToolHotKey: CaseIterable, Sendable {
    case zoom, live, draw, breakTimer, snip, snipOcr, record, panorama, demoMirror
    #if !TEACHLENS_APP_STORE
    case demoType
    #endif

    /// The names HotkeyConflicts uses for this shortcut and the Shift/Option
    /// variants derived from it, so it never clashes with itself.
    var ownNames: Set<String> {
        switch self {
        case .zoom: return ["Static Zoom"]
        case .live: return ["Live Zoom"]
        case .draw: return ["Draw"]
        case .breakTimer: return ["Break Timer"]
        case .snip: return ["Snip", "Snip to File"]
        case .snipOcr: return ["OCR Snip"]
        case .record: return ["Record Screen", "Record Region"]
        case .panorama: return ["Panorama", "Panorama to File"]
        case .demoMirror: return ["DemoMirror", "DemoMirror Region", "DemoMirror Window"]
        #if !TEACHLENS_APP_STORE
        case .demoType: return ["DemoType", "DemoType Reset"]
        #endif
        }
    }

    /// Shortcuts that may be switched off (key code 0).
    var isOptional: Bool {
        switch self {
        case .snipOcr: return true
        #if !TEACHLENS_APP_STORE
        case .demoType: return true
        #endif
        default: return false
        }
    }
}

/// Backs the SwiftUI tool panes (General, Zoom, Live Zoom, Draw, Type,
/// DemoType, Break, Snip, Record, Panorama, DemoMirror). Every change is
/// saved at once; shortcut recording pauses the global hotkeys while a key is
/// being captured, exactly as the AppKit panes did.
@MainActor
final class ToolSettingsModel: NSObject, ObservableObject {
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { store.save(settings) } }
    }
    @Published private(set) var recording: ToolHotKey?
    /// Why the last recorded shortcut was refused, shown under its row.
    @Published private(set) var conflict: (hotKey: ToolHotKey, message: String)?
    @Published var language: AppLanguage = L10n.language

    private let store: SettingsStore
    private let access: UserSelectedResourceAccess
    private let onHotKeyChange: () -> Void
    private let onSuspendHotkeys: () -> Void
    private let onResumeHotkeys: () -> Void
    let requestMicrophone: () -> Void
    let requestSpeechRecognition: () -> Void
    let requestCamera: () -> Void
    let openTrimEditor: () -> Void
    weak var window: NSWindow?
    private var monitor: Any?

    let microphones = AudioDevices.availableMicrophones()
    let cameras = VideoDevices.availableCameras()

    static let colorOptions: [(name: String, rgb: UInt32)] = [
        (L10n.t("Red", "紅"), 0xFF0000), (L10n.t("Green", "綠"), 0x00FF00), (L10n.t("Blue", "藍"), 0x0000FF),
        (L10n.t("Orange", "橘"), 0xFFA500), (L10n.t("Yellow", "黃"), 0xFFFF00), (L10n.t("Pink", "粉紅"), 0xFF69B4),
        (L10n.t("White", "白"), 0xFFFFFF), (L10n.t("Black", "黑"), 0x000000),
    ]

    init(store: SettingsStore, access: UserSelectedResourceAccess,
         onHotKeyChange: @escaping () -> Void, onSuspendHotkeys: @escaping () -> Void,
         onResumeHotkeys: @escaping () -> Void, requestMicrophone: @escaping () -> Void,
         requestSpeechRecognition: @escaping () -> Void, requestCamera: @escaping () -> Void,
         openTrimEditor: @escaping () -> Void) {
        self.store = store
        self.access = access
        self.settings = store.load()
        self.onHotKeyChange = onHotKeyChange
        self.onSuspendHotkeys = onSuspendHotkeys
        self.onResumeHotkeys = onResumeHotkeys
        self.requestMicrophone = requestMicrophone
        self.requestSpeechRecognition = requestSpeechRecognition
        self.requestCamera = requestCamera
        self.openTrimEditor = openTrimEditor
        super.init()
    }

    /// Picks up values changed elsewhere (menus, course modes) when Settings opens.
    func reload() {
        let latest = store.load()
        if latest != settings { settings = latest }
        language = L10n.language
    }

    /// A binding to one setting, with an optional follow-up after it changes.
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>, after: ((T) -> Void)? = nil) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in
                self.settings[keyPath: keyPath] = value
                after?(value)
            }
        )
    }

    // MARK: Shortcuts

    func code(_ hotKey: ToolHotKey) -> (Int, UInt) {
        switch hotKey {
        case .zoom: return (settings.hotKeyCode, settings.hotKeyModifiers)
        case .live: return (settings.liveHotKeyCode, settings.liveHotKeyModifiers)
        case .draw: return (settings.drawHotKeyCode, settings.drawHotKeyModifiers)
        case .breakTimer: return (settings.breakHotKeyCode, settings.breakHotKeyModifiers)
        case .snip: return (settings.snipHotKeyCode, settings.snipHotKeyModifiers)
        case .snipOcr: return (settings.snipOcrHotKeyCode, settings.snipOcrHotKeyModifiers)
        case .record: return (settings.recordHotKeyCode, settings.recordHotKeyModifiers)
        case .panorama: return (settings.panoramaHotKeyCode, settings.panoramaHotKeyModifiers)
        case .demoMirror: return (settings.demoMirrorHotKeyCode, settings.demoMirrorHotKeyModifiers)
        #if !TEACHLENS_APP_STORE
        case .demoType: return (settings.demoTypeHotKeyCode, settings.demoTypeHotKeyModifiers)
        #endif
        }
    }

    private func set(_ hotKey: ToolHotKey, code: Int, modifiers: UInt) {
        switch hotKey {
        case .zoom: settings.hotKeyCode = code; settings.hotKeyModifiers = modifiers
        case .live: settings.liveHotKeyCode = code; settings.liveHotKeyModifiers = modifiers
        case .draw: settings.drawHotKeyCode = code; settings.drawHotKeyModifiers = modifiers
        case .breakTimer: settings.breakHotKeyCode = code; settings.breakHotKeyModifiers = modifiers
        case .snip: settings.snipHotKeyCode = code; settings.snipHotKeyModifiers = modifiers
        case .snipOcr: settings.snipOcrHotKeyCode = code; settings.snipOcrHotKeyModifiers = modifiers
        case .record: settings.recordHotKeyCode = code; settings.recordHotKeyModifiers = modifiers
        case .panorama: settings.panoramaHotKeyCode = code; settings.panoramaHotKeyModifiers = modifiers
        case .demoMirror: settings.demoMirrorHotKeyCode = code; settings.demoMirrorHotKeyModifiers = modifiers
        #if !TEACHLENS_APP_STORE
        case .demoType: settings.demoTypeHotKeyCode = code; settings.demoTypeHotKeyModifiers = modifiers
        #endif
        }
    }

    func display(_ hotKey: ToolHotKey) -> String {
        if recording == hotKey { return L10n.t("Type shortcut… (Esc cancels)", "請按快捷鍵…（Esc 取消）") }
        let (code, modifiers) = code(hotKey)
        if code == 0 { return L10n.t("None", "無") }
        return SettingsWindowController.describe(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
    }

    /// Starts recording a shortcut, or stops if one is already being recorded.
    func toggleRecording(_ hotKey: ToolHotKey) {
        if recording != nil {
            finishRecording()
            return
        }
        conflict = nil
        recording = hotKey
        // Suspend the global hotkeys only while capturing, so the pressed keys
        // are recorded instead of triggering their action (issue #22).
        onSuspendHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Only Sendable values cross into the main-actor call; the event
            // itself is returned (passed on) or swallowed out here.
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated { self?.capture(keyCode: keyCode, flags: flags) ?? false }
            return consumed ? nil : event
        }
    }

    /// Handles a key pressed while recording; returns true when it was used.
    private func capture(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard let hotKey = recording else { return false }
        if keyCode == 53 { // Esc cancels.
            finishRecording()
            return true
        }
        let modifiers = flags.intersection([.command, .control, .option, .shift])
        guard !modifiers.isEmpty else {
            // A global hotkey needs at least one modifier.
            NSSound.beep()
            return true
        }
        let newCode = Int(keyCode)
        let wanted = HotkeyConflicts.normalized(modifiers.rawValue)
        let own = hotKey.ownNames
        if let clash = HotkeyConflicts.registeredShortcuts(app: settings).first(where: {
            !own.contains($0.name) && $0.keyCode == newCode && HotkeyConflicts.normalized($0.modifiers) == wanted
        })?.name {
            NSSound.beep()
            conflict = (hotKey, L10n.t("Already used by \(ShortcutCard.title(for: clash)). Try another.",
                                       "已被「\(ShortcutCard.title(for: clash))」使用，請換一組。"))
            return true
        }
        set(hotKey, code: newCode, modifiers: modifiers.rawValue)
        finishRecording()
        onHotKeyChange()
        return true
    }

    /// Turns an optional shortcut off.
    func clear(_ hotKey: ToolHotKey) {
        guard hotKey.isOptional else { return }
        set(hotKey, code: 0, modifiers: 0)
        onHotKeyChange()
    }

    func finishRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil {
            recording = nil
            onResumeHotkeys()
        }
    }

    // MARK: General

    func setLaunchAtLogin(_ enable: Bool) {
        settings.launchAtLogin = enable
        do {
            try LaunchAtLogin.setEnabled(enable)
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("Couldn’t update the login item", "無法更新登入項目")
            alert.informativeText = L10n.t(
                "TeachLens saved your startup preference and will try again next launch. macOS reported: \(error.localizedDescription)",
                "已保存設定，下次啟動時會再試一次。系統訊息：\(error.localizedDescription)")
            alert.runModal()
        }
    }

    func setLanguage(_ language: AppLanguage) {
        guard language != L10n.language else { return }
        L10n.language = language
        NotificationCenter.default.post(name: L10n.didChangeNotification, object: nil)
    }

    // MARK: Files

    enum FileChoice { case breakSound, breakBackground, snipFolder, demoType }

    func choose(_ choice: FileChoice) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        switch choice {
        case .breakSound:
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.audio]
            panel.title = L10n.t("TeachLens: Specify Sound File", "TeachLens：選擇聲音檔")
        case .breakBackground:
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.image]
            panel.title = L10n.t("TeachLens: Specify Background File", "TeachLens：選擇背景圖片")
        case .snipFolder:
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = L10n.t("Choose", "選擇")
            panel.title = L10n.t("TeachLens: Choose Snip Folder", "TeachLens：選擇截圖資料夾")
        case .demoType:
            panel.canChooseDirectories = false
            panel.title = L10n.t("TeachLens: Specify DemoType File", "TeachLens：選擇 DemoType 檔案")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch choice {
        case .breakSound:
            guard saveSelection(url, for: .breakSound) else { return }
            settings.breakSoundFile = url.path
        case .breakBackground:
            guard saveSelection(url, for: .breakBackground) else { return }
            settings.breakBackgroundFile = url.path
        case .snipFolder:
            guard saveSelection(url, for: .snipDirectory) else { return }
            settings.snipSaveDirectory = url.path
        case .demoType:
            settings.demoTypeFile = url.path
        }
    }

    private func saveSelection(_ url: URL, for resource: UserSelectedResource) -> Bool {
        do {
            try access.saveSelection(url, for: resource)
            return true
        } catch {
            if DistributionChannel.isAppStore {
                NSAlert(error: error).runModal()
                return false
            }
            return true
        }
    }

    var snipFolderDisplay: String {
        settings.snipSaveDirectory.trimmingCharacters(in: .whitespaces).isEmpty
            ? ImageExporter.defaultSaveDirectory().path : settings.snipSaveDirectory
    }

    // MARK: Typing font

    var typingFont: NSFont {
        AnnotationController.typingFont(named: settings.typingFontName, size: settings.typingFontSize)
    }

    func chooseFont() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(typingFont, isMultiple: false)
        if let window { window.makeFirstResponder(window) }
        manager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        let manager = sender as? NSFontManager ?? NSFontManager.shared
        let font = manager.convert(typingFont)
        settings.typingFontName = font.fontName
        settings.typingFontSize = font.pointSize
    }

    var noiseCancellationSupported: Bool {
        settings.recordMicrophone && AudioDevices.supportsWindNoiseRemoval(deviceID: settings.microphoneDeviceID)
    }
}

// MARK: - Shared pieces

/// A pane in the same grouped-form style as the teaching panes.
private struct ToolPane<Content: View>: View {
    let help: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form {
            Section {
                Label(help, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 540, height: 460)
    }
}

/// "Shortcut  [⌨ ⌃1]" with recording state and any clash message.
private struct HotKeyRow: View {
    @ObservedObject var model: ToolSettingsModel
    let title: String
    let hotKey: ToolHotKey

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Button {
                    model.toggleRecording(hotKey)
                } label: {
                    Label(model.display(hotKey), systemImage: model.recording == hotKey ? "record.circle" : "keyboard")
                        .frame(minWidth: 110)
                }
                if hotKey.isOptional, model.code(hotKey).0 != 0 {
                    Button { model.clear(hotKey) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(L10n.t("Turn this shortcut off", "關閉這個快捷鍵"))
                        .accessibilityLabel(L10n.t("Turn off", "關閉"))
                }
            }
        }
        if let conflict = model.conflict, conflict.hotKey == hotKey {
            Label(conflict.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }
}

/// A file or folder path with a Browse button.
private struct PathRow: View {
    let title: String
    let path: String
    let action: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(path.isEmpty ? L10n.t("No file selected", "尚未選擇檔案") : (path as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(path)
                Button(action: action) { Label(L10n.t("Browse…", "瀏覽…"), systemImage: "folder") }
            }
        }
    }
}

// MARK: - Panes

struct GeneralToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("TeachLens runs in the menu bar. Choose a pane on the left to set it up.",
                              "TeachLens 常駐在選單列。從左側選擇要設定的功能。")) {
            Section {
                Toggle(isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Label(L10n.t("Launch TeachLens when I log in", "登入時自動啟動 TeachLens"), systemImage: "power")
                }
                .disabled(!LaunchAtLogin.isAvailable)
                .help(LaunchAtLogin.isAvailable ? "" : L10n.t("Launch at login requires running TeachLens from TeachLens.app.",
                                                              "必須從 TeachLens.app 執行才能設定登入時啟動。"))
                Picker(selection: Binding(get: { model.language }, set: { model.language = $0; model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Label(L10n.t("Language", "語言"), systemImage: "globe")
                }
            }
            Section(L10n.t("About", "關於")) {
                LabeledContent(L10n.t("Version", "版本"), value: "\(AppInfo.version) (\(AppInfo.commit))")
                Text(AppInfo.copyright).foregroundStyle(.secondary)
                Text(AppInfo.attribution).foregroundStyle(.secondary)
                Link(destination: URL(string: AppInfo.repositoryURL)!) {
                    Label("github.com/FW1201/TeachLens", systemImage: "link")
                }
            }
        }
    }
}

struct ZoomToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("Zoom with the mouse wheel or Option+↑/↓; exit with Esc or a right-click.",
                              "用滑鼠滾輪或 ⌥↑／⌥↓ 調整倍率；按 Esc 或右鍵離開。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Zoom shortcut", "放大快捷鍵"), hotKey: .zoom)
                Picker(L10n.t("Initial magnification", "初始倍率"), selection: model.binding(\.defaultZoomFactor)) {
                    ForEach(AppSettings.zoomLevels, id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                }
                Toggle(L10n.t("Animate zoom in and out", "放大與縮小時顯示動畫"), isOn: model.binding(\.animateZoom))
                Toggle(L10n.t("Smooth the zoomed image", "平滑放大後的影像"), isOn: model.binding(\.smoothImage))
            }
        }
    }
}

struct LiveZoomToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("Magnifies the live screen so motion stays visible while zoomed.",
                              "放大即時畫面，放大時動態內容仍持續更新。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Live zoom shortcut", "即時放大快捷鍵"), hotKey: .live)
            }
        }
    }
}

struct DrawToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("Left-click to draw, right-click to stop; ⌘Z undoes, E erases all.",
                              "左鍵開始畫，右鍵結束；⌘Z 復原，E 全部清除。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Draw without zoom", "不放大直接畫"), hotKey: .draw)
            }
            Section(L10n.t("While drawing", "畫筆操作")) {
                tip("lineweight", L10n.t("Pen width", "筆寬"), L10n.t("Mouse wheel, [ and ], or Shift+↑/↓", "滑鼠滾輪、[ ]，或 Shift+↑／↓"))
                tip("paintpalette", L10n.t("Colors", "顏色"), L10n.t("R G B O Y P W K", "R G B O Y P W K：紅綠藍橘黃粉白黑"))
                tip("highlighter", L10n.t("Highlighter", "螢光筆"), L10n.t("Shift + a colour key", "Shift＋顏色鍵"))
                tip("square.on.circle", L10n.t("Shapes", "圖形"),
                    L10n.t("Shift: line · Control: box · Tab: ellipse · Shift+Control: arrow",
                           "Shift 直線 · Control 矩形 · Tab 橢圓 · Shift+Control 箭頭"))
                tip("rectangle.inset.filled", L10n.t("Board", "板面"), L10n.t("Ctrl+W white / Ctrl+K black", "Ctrl+W 白板／Ctrl+K 黑板"))
            }
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        LabeledContent {
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

struct TypeToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("While drawing, press T to type (Shift+T: right-aligned); ↑/↓ change the size.",
                              "畫筆模式下按 T 打字（Shift+T 靠右）；↑／↓ 調整字級。")) {
            Section {
                LabeledContent(L10n.t("Typing font", "打字字體")) {
                    Button { model.chooseFont() } label: { Label(L10n.t("Select Font…", "選擇字體…"), systemImage: "textformat") }
                }
                let preview = SettingsWindowController.fontSamplePreviewFont(name: model.settings.typingFontName,
                                                                            size: model.settings.typingFontSize)
                Text(L10n.t("Sample — \(preview.displayName ?? preview.fontName) \(Int(model.settings.typingFontSize))pt",
                            "範例 — \(preview.displayName ?? preview.fontName) \(Int(model.settings.typingFontSize))pt"))
                    .font(Font(preview as CTFont))
                    .lineLimit(1)
            }
        }
    }
}

#if !TEACHLENS_APP_STORE
struct DemoTypeToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("Types the snippets from a text file; separate snippets with [end].",
                              "依序輸入文字檔中的片段；片段之間用 [end] 分隔。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Auto typing shortcut", "自動打字快捷鍵"), hotKey: .demoType)
                PathRow(title: L10n.t("Input file", "輸入檔案"), path: model.settings.demoTypeFile) { model.choose(.demoType) }
                LabeledContent(L10n.t("Typing speed", "打字速度")) {
                    HStack {
                        Text(L10n.t("Slow", "慢")).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(model.settings.demoTypeSpeed) },
                                              set: { model.settings.demoTypeSpeed = min(max(Int($0), 10), 100) }),
                               in: 10...100)
                            .frame(width: 180)
                        Text(L10n.t("Fast", "快")).foregroundStyle(.secondary)
                    }
                }
                Toggle(L10n.t("Drive input with my typing", "由我打字推進"), isOn: model.binding(\.demoTypeUserDriven))
            }
            Section {
                Text(L10n.t("Keywords: [pause:n] · [paste]…[/paste] · [enter] [up] [down] [left] [right]. Esc stops.",
                            "關鍵字：[pause:n] · [paste]…[/paste] · [enter] [up] [down] [left] [right]。Esc 停止。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
#endif

struct BreakToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    private static let positions = [
        L10n.t("Top-left", "左上"), L10n.t("Top", "上"), L10n.t("Top-right", "右上"),
        L10n.t("Left", "左"), L10n.t("Center", "中央"), L10n.t("Right", "右"),
        L10n.t("Bottom-left", "左下"), L10n.t("Bottom", "下"), L10n.t("Bottom-right", "右下"),
    ]

    var body: some View {
        let usesImage = model.settings.breakBackgroundMode == 2
        ToolPane(help: L10n.t("Shows a full-screen countdown; arrow keys adjust the time, Esc exits.",
                              "顯示全螢幕倒數；方向鍵調整時間，Esc 離開。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Start timer", "開始計時"), hotKey: .breakTimer)
                Stepper(value: Binding(get: { model.settings.breakDurationMinutes },
                                       set: { model.settings.breakDurationMinutes = min(max($0, 1), 99) }),
                        in: 1...99) {
                    LabeledContent(L10n.t("Duration", "時間長度"),
                                   value: L10n.t("\(model.settings.breakDurationMinutes) minutes",
                                                 "\(model.settings.breakDurationMinutes) 分鐘"))
                }
                Toggle(L10n.t("Show time elapsed after it ends", "時間到後顯示已超過的時間"),
                       isOn: model.binding(\.breakShowExpiredTime))
            }
            Section(L10n.t("Look", "外觀")) {
                colorPicker(L10n.t("Timer color", "計時器顏色"), \.breakTextColorRGB)
                colorPicker(L10n.t("Background", "背景"), \.breakBackgroundColorRGB)
                Picker(L10n.t("Position", "位置"), selection: model.binding(\.breakTimerPosition)) {
                    ForEach(Array(Self.positions.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                }
                Picker(L10n.t("Opacity", "不透明度"), selection: model.binding(\.breakOpacity)) {
                    ForEach(Array(stride(from: 10, through: 100, by: 10)), id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker(L10n.t("Backdrop", "背景樣式"), selection: model.binding(\.breakBackgroundMode)) {
                    Text(L10n.t("No image", "無圖片")).tag(0)
                    Text(L10n.t("Faded desktop", "淡化桌面")).tag(1)
                    Text(L10n.t("Image file", "圖片檔")).tag(2)
                }
                PathRow(title: L10n.t("Image file", "圖片檔"), path: model.settings.breakBackgroundFile) {
                    model.choose(.breakBackground)
                }
                .disabled(!usesImage)
                Toggle(L10n.t("Scale image to the screen", "圖片縮放至螢幕大小"), isOn: model.binding(\.breakBackgroundStretch))
                    .disabled(!usesImage)
            }
            Section(L10n.t("Sound", "聲音")) {
                Toggle(L10n.t("Play a sound when time is up", "時間到時播放聲音"), isOn: model.binding(\.breakPlaySound))
                PathRow(title: L10n.t("Sound file", "聲音檔"), path: model.settings.breakSoundFile) { model.choose(.breakSound) }
            }
        }
    }

    private func colorPicker(_ title: String, _ keyPath: WritableKeyPath<AppSettings, UInt32>) -> some View {
        Picker(title, selection: model.binding(keyPath)) {
            ForEach(ToolSettingsModel.colorOptions, id: \.rgb) { option in
                Text(option.name).tag(option.rgb)
            }
        }
    }
}

struct SnipToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("Drag a region to copy it; hold Shift to save a PNG. The OCR shortcut copies the text instead.",
                              "拖曳範圍即複製；加 Shift 存成 PNG。文字辨識快捷鍵會改為複製文字。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Snip shortcut", "截圖快捷鍵"), hotKey: .snip)
                HotKeyRow(model: model, title: L10n.t("Text recognition", "文字辨識快捷鍵"), hotKey: .snipOcr)
            }
            Section {
                Toggle(L10n.t("Dictate a note during clipboard snips", "截圖到剪貼簿時可以口述"),
                       isOn: model.binding(\.snipDictationEnabled) { on in if on { model.requestSpeechRecognition() } })
                MicrophonePicker(model: model, title: L10n.t("Dictation microphone", "口述用麥克風"))
                    .disabled(!model.settings.snipDictationEnabled)
            }
            Section(L10n.t("Saving", "存檔")) {
                Toggle(L10n.t("Also copy to the clipboard when saving", "存檔時也複製到剪貼簿"),
                       isOn: model.binding(\.copySnipToClipboardOnSave))
                Toggle(L10n.t("Save to a folder instead of asking", "直接存到資料夾，不每次詢問"),
                       isOn: model.binding(\.saveSnipToDirectory))
                PathRow(title: L10n.t("Folder", "資料夾"), path: model.snipFolderDisplay) { model.choose(.snipFolder) }
                    .disabled(!model.settings.saveSnipToDirectory)
            }
        }
    }
}

private struct MicrophonePicker: View {
    @ObservedObject var model: ToolSettingsModel
    let title: String

    var body: some View {
        Picker(title, selection: model.binding(\.microphoneDeviceID)) {
            ForEach(model.microphones, id: \.id) { device in
                Text(device.id.isEmpty ? L10n.t("Default", "預設") : device.name).tag(device.id)
            }
        }
    }
}

struct RecordToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    private static let webcamPositions: [(String, Int)] = [
        (L10n.t("Top-left", "左上"), 0), (L10n.t("Top-right", "右上"), 1), (L10n.t("Center", "中央"), 4),
        (L10n.t("Bottom-left", "左下"), 2), (L10n.t("Bottom-right", "右下"), 3),
    ]

    var body: some View {
        let webcamOn = model.settings.webcamEnabled
        ToolPane(help: L10n.t("Records the screen to MP4; hold Shift to record a region. Press again to stop.",
                              "錄製全螢幕為 MP4；加 Shift 錄製區域。再按一次停止。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Record shortcut", "錄影快捷鍵"), hotKey: .record)
                LabeledContent(L10n.t("Edit an existing video", "剪輯現有影片")) {
                    Button { model.openTrimEditor() } label: { Label(L10n.t("Trim…", "剪輯…"), systemImage: "scissors") }
                }
            }
            Section(L10n.t("Audio", "聲音")) {
                Toggle(L10n.t("Capture system audio", "錄製系統聲音"), isOn: model.binding(\.recordSystemAudio))
                Toggle(L10n.t("Capture the microphone", "錄製麥克風"),
                       isOn: model.binding(\.recordMicrophone) { on in if on { model.requestMicrophone() } })
                MicrophonePicker(model: model, title: L10n.t("Microphone", "麥克風"))
                    .disabled(!model.settings.recordMicrophone)
                Toggle(isOn: Binding(get: { model.settings.recordNoiseCancellation && model.noiseCancellationSupported },
                                     set: { model.settings.recordNoiseCancellation = $0 })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("Noise cancellation", "降噪"))
                        if !model.noiseCancellationSupported {
                            Text(L10n.t("Needs macOS 15 and a microphone that supports it.", "需要 macOS 15 以上與支援的麥克風。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!model.noiseCancellationSupported)
            }
            Section(L10n.t("Webcam overlay", "相機子母畫面")) {
                Toggle(L10n.t("Show the webcam in recordings", "錄影時顯示相機畫面"),
                       isOn: model.binding(\.webcamEnabled) { on in if on { model.requestCamera() } })
                Picker(L10n.t("Camera", "相機"), selection: model.binding(\.webcamDeviceID)) {
                    ForEach(model.cameras, id: \.id) { camera in
                        Text(camera.id.isEmpty ? L10n.t("Default", "預設") : camera.name).tag(camera.id)
                    }
                }
                .disabled(!webcamOn)
                Picker(L10n.t("Position", "位置"), selection: model.binding(\.webcamPosition)) {
                    ForEach(Self.webcamPositions, id: \.1) { Text($0.0).tag($0.1) }
                }
                .disabled(!webcamOn)
                Picker(L10n.t("Size", "大小"), selection: model.binding(\.webcamSize)) {
                    Text(L10n.t("Small", "小")).tag(0)
                    Text(L10n.t("Medium", "中")).tag(1)
                    Text(L10n.t("Large", "大")).tag(2)
                    Text(L10n.t("X-Large", "特大")).tag(3)
                    Text(L10n.t("Full screen", "全螢幕")).tag(4)
                }
                .disabled(!webcamOn)
                Picker(L10n.t("Shape", "形狀"), selection: model.binding(\.webcamShape)) {
                    Text(L10n.t("Rectangle", "矩形")).tag(0)
                    Text(L10n.t("Rounded rectangle", "圓角矩形")).tag(1)
                    Text(L10n.t("Rounded square", "圓角正方形")).tag(2)
                    Text(L10n.t("Circle", "圓形")).tag(3)
                }
                .disabled(!webcamOn || model.settings.webcamSize == 4)
            }
        }
    }
}

struct PanoramaToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("Drag over scrollable content, scroll, then press again to stitch one long image.",
                              "框選可捲動的內容並捲動，再按一次即拼接成長圖。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Panorama shortcut", "長截圖快捷鍵"), hotKey: .panorama)
            }
        }
    }
}

struct DemoMirrorToolPane: View {
    @ObservedObject var model: ToolSettingsModel

    var body: some View {
        ToolPane(help: L10n.t("Mirrors the screen, a region or a window onto a second display.",
                              "把螢幕、區域或視窗鏡像到第二台顯示器。")) {
            Section {
                HotKeyRow(model: model, title: L10n.t("Mirror shortcut", "鏡像快捷鍵"), hotKey: .demoMirror)
                Text(L10n.t("Shortcut: whole screen · with Shift: region · with Option: window under the pointer.",
                            "快捷鍵：整個螢幕 · 加 Shift：區域 · 加 Option：游標下的視窗。"))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(isOn: model.binding(\.demoMirrorTrackWindowRegion)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("Track the window region", "追蹤視窗區域"))
                        Text(L10n.t("Zoom and drawing appear in place.", "讓放大與畫筆顯示在原位置。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
