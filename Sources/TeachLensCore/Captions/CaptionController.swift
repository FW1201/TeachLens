import AppKit
import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct CaptionSettings: Codable, Equatable, Sendable {
    var localeIdentifier = "zh-TW"
    var fontSize: Double = 30
    var atTop = false
    var toggleKeyCode = 8          // kVK_ANSI_C
    var toggleModifiers: UInt = (1 << 18) | (1 << 17) // Control+Shift

    static let languages: [(id: String, title: String)] = [
        ("zh-TW", "中文（台灣）"), ("zh-CN", "中文（简体）"), ("en-US", "English (US)"),
        ("en-GB", "English (UK)"), ("ja-JP", "日本語"), ("ko-KR", "한국어"),
    ]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case localeIdentifier, fontSize, atTop, toggleKeyCode, toggleModifiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CaptionSettings()
        localeIdentifier = try c.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? d.localeIdentifier
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        atTop = try c.decodeIfPresent(Bool.self, forKey: .atTop) ?? d.atTop
        toggleKeyCode = try c.decodeIfPresent(Int.self, forKey: .toggleKeyCode) ?? d.toggleKeyCode
        toggleModifiers = try c.decodeIfPresent(UInt.self, forKey: .toggleModifiers) ?? d.toggleModifiers
    }
}

struct CaptionSettingsStore {
    static let defaultsKey = "captionSettings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> CaptionSettings {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let settings = try? JSONDecoder().decode(CaptionSettings.self, from: data) else { return CaptionSettings() }
        return settings
    }

    func save(_ settings: CaptionSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// Feeds microphone buffers to the current recognition request from the
/// audio thread.
final class CaptionAudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }

    /// Built outside any actor so the audio thread never trips an isolation check.
    nonisolated static func tapBlock(_ feed: CaptionAudioFeed) -> AVAudioNodeTapBlock {
        { buffer, _ in feed.append(buffer) }
    }
}

@MainActor
final class CaptionOverlayModel: ObservableObject {
    @Published var text = ""
    @Published var fontSize: Double = 30
    @Published var atTop = false
    @Published var status: String?
    /// Distance from the screen edges, moved so captions never sit on top of
    /// the keystroke pills or a video call's control bar.
    /// Microphone state for the status light, and the recognition language.
    @Published var listening = false
    @Published var language = "中"
    @Published var topPadding: CGFloat = 72
    @Published var bottomPadding: CGFloat = 150
}

/// Live captions from the microphone (on-device speech recognition when the
/// language supports it) and a timestamped transcript for export.
@MainActor
final class CaptionController: NSObject, NSMenuItemValidation {
    private let store: CaptionSettingsStore
    private(set) var settings: CaptionSettings
    private(set) var isRunning = false

    private let model = CaptionOverlayModel()
    private var panel: NSPanel?
    private let audioEngine = AVAudioEngine()
    private let feed = CaptionAudioFeed()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var requestGeneration = 0
    private var tracker = CaptionSentenceTracker()
    private var timer: Timer?
    private var sessionStart: TimeInterval = 0
    private var lastShownAt: TimeInterval = 0
    private var sampleGeneration = 0

    private(set) var transcript: [CaptionSegment] = []
    private var recordingStart: TimeInterval?
    private(set) var lastRecording: (start: TimeInterval, end: TimeInterval)?

    var onHotkeyChange: (() -> Void)?

    init(store: CaptionSettingsStore = CaptionSettingsStore()) {
        self.store = store
        self.settings = store.load()
        super.init()
        model.fontSize = settings.fontSize
        model.atTop = settings.atTop
        model.language = Self.shortLanguage(settings.localeIdentifier)
    }

    /// A one- or two-character label for the caption chip: 中, EN, 日, 한.
    static func shortLanguage(_ id: String) -> String {
        if id.hasPrefix("zh") { return "中" }
        if id.hasPrefix("ja") { return "日" }
        if id.hasPrefix("ko") { return "한" }
        return String(id.prefix(2)).uppercased()
    }

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    var windowNumberForCaptureExclusion: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    func update(_ change: (inout CaptionSettings) -> Void) {
        let old = settings
        change(&settings)
        settings.fontSize = min(max(settings.fontSize, 16), 72)
        guard settings != old else { return }
        store.save(settings)
        model.language = Self.shortLanguage(settings.localeIdentifier)
        model.fontSize = settings.fontSize
        model.atTop = settings.atTop
        if old.localeIdentifier != settings.localeIdentifier && isRunning {
            stop()
            start()
        }
        if old.toggleKeyCode != settings.toggleKeyCode || old.toggleModifiers != settings.toggleModifiers {
            onHotkeyChange?()
        }
    }

    // MARK: Start / stop

    @objc func toggle() {
        isRunning ? stop() : start()
    }

    func setEnabled(_ on: Bool) {
        if on != isRunning { on ? start() : stop() }
    }

    func start() {
        guard !isRunning else { return }
        requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.showPermissionAlert()
                return
            }
            self.beginSession()
        }
    }

    func stop() {
        guard isRunning else { return }
        flushSentence(force: true)
        isRunning = false
        model.listening = false
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        feed.setRequest(nil)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        model.text = ""
        panel?.orderOut(nil)
    }

    private func requestPermissions(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let speechOK: @Sendable (Bool) -> Void = { micGranted in
            guard micGranted else {
                Task { @MainActor in completion(false) }
                return
            }
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                let granted = status == .authorized
                Task { @MainActor in completion(granted) }
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            speechOK(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable granted in speechOK(granted) }
        default:
            completion(false)
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.t("Allow Microphone and Speech Recognition for captions",
                                   "字幕需要「麥克風」與「語音辨識」權限")
        alert.informativeText = L10n.t(
            "Turn on TeachLens in System Settings ▸ Privacy & Security ▸ Microphone and Speech Recognition, then try again.",
            "請到「系統設定 ▸ 隱私權與安全性」的「麥克風」與「語音辨識」開啟 TeachLens，再重試一次。"
        )
        alert.addButton(withTitle: L10n.t("Open Settings…", "打開系統設定…"))
        alert.addButton(withTitle: L10n.t("Not Now", "稍後"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }

    private func beginSession() {
        let locale = Locale(identifier: settings.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            model.status = L10n.t("Speech recognition isn’t available for this language.", "這個語言目前無法使用語音辨識。")
            ensurePanel()
            return
        }
        self.recognizer = recognizer

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: CaptionAudioFeed.tapBlock(feed))
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            model.status = L10n.t("The microphone couldn’t start.", "麥克風無法啟動。")
            ensurePanel()
            return
        }

        if transcript.isEmpty { sessionStart = Self.now() }
        isRunning = true
        model.listening = true
        model.status = nil
        ensurePanel()
        startRequest()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func startRequest() {
        guard isRunning, let recognizer else { return }
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true
        feed.setRequest(request)
        requestGeneration += 1
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self, generation: requestGeneration))
    }

    /// Built outside the actor: Speech calls it on its own queue.
    nonisolated private static func resultHandler(
        for controller: CaptionController,
        generation: Int
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak controller] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                controller?.handle(text: text, isFinal: isFinal, failed: failed, generation: generation)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard isRunning, generation == requestGeneration else { return }
        let now = Self.now() - sessionStart
        if let text {
            tracker.partial(text, at: now)
            model.text = Self.lastLines(text)
            lastShownAt = Self.now()
        }
        if isFinal || failed {
            flushSentence(force: true)
            startRequest()
        }
    }

    private func tick() {
        guard isRunning else { return }
        if flushSentence(force: false) {
            startRequest()
        }
        if !model.text.isEmpty, Self.now() - lastShownAt > 4 {
            model.text = ""
        }
    }

    @discardableResult
    private func flushSentence(force: Bool) -> Bool {
        guard let segment = tracker.finishIfDue(at: Self.now() - sessionStart, force: force) else { return false }
        transcript.append(segment)
        return true
    }

    /// Keeps the last ~80 characters so captions stay at two lines.
    static func lastLines(_ text: String, limit: Int = 80) -> String {
        guard text.count > limit else { return text }
        let tail = text.suffix(limit)
        if let space = tail.firstIndex(of: " "), tail.distance(from: tail.startIndex, to: space) < 20 {
            return String(tail[tail.index(after: space)...])
        }
        return "…" + tail
    }

    // MARK: Recording sync

    /// True when captions were recognised during the last recording.
    var hasCaptionsForLastRecording: Bool {
        guard let range = lastRecording else { return false }
        return !CaptionFormatter.slice(transcript, from: range.start, to: range.end).isEmpty
    }

    func recordingStateChanged(_ recording: Bool) {
        let t = Self.now() - sessionStart
        if recording {
            if transcript.isEmpty && !isRunning { sessionStart = Self.now() }
            recordingStart = max(0, Self.now() - sessionStart)
        } else if let start = recordingStart {
            lastRecording = (start, t)
            recordingStart = nil
        }
    }

    // MARK: Overlay

    /// Shows a sample caption without the microphone (Settings ▸ Check & Test).
    @discardableResult
    func showSample() -> Bool {
        // Do not replace real speech with demo text during a live lesson.
        guard !isRunning else { return false }
        sampleGeneration += 1
        let generation = sampleGeneration
        ensurePanel()
        model.status = nil
        model.text = L10n.t("This is a sample caption. Live captions appear here while you speak.",
                            "這是字幕示範。開啟即時字幕後，你說的話會顯示在這裡。")
        lastShownAt = Self.now()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !self.isRunning, self.sampleGeneration == generation else { return }
            self.model.text = ""
            self.panel?.orderOut(nil)
        }
        return true
    }

    /// Keeps captions clear of the keystroke HUD: `keystrokes` is how far the
    /// pills reach from their edge, `meetingInset` the room kept for a call's
    /// control bar.
    func avoid(keystrokes settings: KeystrokeSettings) {
        let reach = CGFloat(settings.occupiedHeight)
        let meeting = CGFloat(settings.avoidMeetingBar ? KeystrokeSettings.meetingBarHeight : 0)
        let pillsAtTop = settings.enabled && settings.position.isTop
        let pillsAtBottom = settings.enabled && !settings.position.isTop
        model.topPadding = max(72, pillsAtTop ? reach + 16 : 0)
        model.bottomPadding = max(150 + meeting, pillsAtBottom ? reach + 16 : 0)
    }

    private func ensurePanel() {
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let hosting = NSHostingView(rootView: CaptionOverlayView(model: model))
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            self.panel = panel
        }
        if let screen = PresentationDisplay.screen() {
            panel?.setFrame(screen.frame, display: true)
        }
        panel?.orderFrontRegardless()
    }

    // MARK: Export

    private func export(_ format: String, segments: [CaptionSegment], name: String) {
        guard !segments.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L10n.t("No captions yet", "還沒有字幕內容")
            alert.informativeText = L10n.t("Turn on live captions and speak, then export again.",
                                           "請先開啟即時字幕並說話，再匯出。")
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).\(format)"
        panel.allowedContentTypes = [UTType(filenameExtension: format) ?? .plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body: String
        switch format {
        case "srt": body = CaptionFormatter.srt(segments)
        case "vtt": body = CaptionFormatter.vtt(segments)
        default: body = CaptionFormatter.plainText(segments)
        }
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            ExportFeedback.saved(url)
        } catch {
            ExportFeedback.failed(error)
        }
    }

    private func currentTranscript() -> [CaptionSegment] {
        if isRunning { flushSentence(force: true); startRequest() }
        return transcript
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f.string(from: Date())
    }

    @objc func exportSRT() { export("srt", segments: currentTranscript(), name: "TeachLens Transcript \(Self.dateStamp())") }
    @objc func exportVTT() { export("vtt", segments: currentTranscript(), name: "TeachLens Transcript \(Self.dateStamp())") }
    @objc func exportTXT() { export("txt", segments: currentTranscript(), name: "TeachLens Transcript \(Self.dateStamp())") }

    @objc func exportLastRecording() {
        guard let range = lastRecording else { return }
        export("srt", segments: CaptionFormatter.slice(currentTranscript(), from: range.start, to: range.end),
               name: "TeachLens Recording \(Self.dateStamp())")
    }

    @objc func clearTranscript() {
        transcript = []
        lastRecording = nil
        sessionStart = Self.now()
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        update { $0.localeIdentifier = id }
    }

    @objc private func larger() { update { $0.fontSize += 4 } }
    @objc private func smaller() { update { $0.fontSize -= 4 } }
    @objc private func togglePosition() { update { $0.atTop.toggle() } }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ represented: String? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = represented
            menu.addItem(item)
        }
        for language in CaptionSettings.languages {
            add(language.title, #selector(setLanguage(_:)), language.id)
        }
        menu.addItem(.separator())
        add(L10n.t("Larger Text", "放大字幕"), #selector(larger))
        add(L10n.t("Smaller Text", "縮小字幕"), #selector(smaller))
        add(L10n.t("Show at Top", "顯示在上方"), #selector(togglePosition))
        menu.addItem(.separator())
        add(L10n.t("Export Transcript (.srt)…", "匯出逐字稿（.srt）…"), #selector(exportSRT))
        add(L10n.t("Export Transcript (.vtt)…", "匯出逐字稿（.vtt）…"), #selector(exportVTT))
        add(L10n.t("Export Transcript (.txt)…", "匯出逐字稿（.txt）…"), #selector(exportTXT))
        add(L10n.t("Export Captions for Last Recording (.srt)…", "匯出上一段錄影的字幕（.srt）…"), #selector(exportLastRecording))
        add(L10n.t("Clear Transcript", "清除逐字稿"), #selector(clearTranscript))
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggle):
            menuItem.state = isRunning ? .on : .off
        case #selector(setLanguage(_:)):
            menuItem.state = (menuItem.representedObject as? String) == settings.localeIdentifier ? .on : .off
        case #selector(togglePosition):
            menuItem.state = settings.atTop ? .on : .off
        case #selector(exportLastRecording):
            return lastRecording != nil
        case #selector(clearTranscript):
            return !transcript.isEmpty
        default:
            break
        }
        return true
    }
}

struct CaptionOverlayView: View {
    @ObservedObject var model: CaptionOverlayModel

    var body: some View {
        VStack {
            if model.atTop {
                caption
                Spacer()
            } else {
                Spacer()
                caption
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, model.topPadding)
        .padding(.bottom, model.bottomPadding)
        .animation(.easeOut(duration: 0.25), value: model.bottomPadding)
        .animation(.easeOut(duration: 0.2), value: model.text)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var caption: some View {
        let text = model.status ?? model.text
        if !text.isEmpty {
            HStack(alignment: .center, spacing: 12) {
                // Status light (green: listening, orange: problem) and language.
                VStack(spacing: 4) {
                    Circle()
                        .fill(model.status != nil ? Color.orange : (model.listening ? Color.green : Color.gray))
                        .frame(width: 8, height: 8)
                    Text(model.language)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .modifier(CaptionBackground())
            .frame(maxWidth: 1100)
            .transition(.opacity)
        }
    }
}

/// Captions sit on dark glass (Liquid Glass on macOS 26) so they match the
/// keystroke pills and stay legible over video; opaque with Reduce Transparency.
private struct CaptionBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if reduceTransparency || !KeystrokeGlassSupport.isLiquidGlassAvailable {
            content.background(shape.fill(Color.black.opacity(0.75)))
        } else {
            glass(content, shape: shape)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content, shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.black.opacity(0.5)), in: shape)
        } else {
            content.background(shape.fill(Color.black.opacity(0.75)))
        }
        #else
        content.background(shape.fill(Color.black.opacity(0.75)))
        #endif
    }
}
