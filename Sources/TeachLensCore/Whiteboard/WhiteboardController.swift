import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WhiteboardTool: String, CaseIterable, Sendable {
    case pen, highlighter, eraser
}

@MainActor
final class WhiteboardModel: ObservableObject {
    @Published var document: WhiteboardDocument
    @Published var tool: WhiteboardTool = .pen
    @Published var color: WhiteboardColor = WhiteboardColor.palette[0]
    @Published var width: Double = 4
    private var undoStack: [WhiteboardDocument] = []

    init(document: WhiteboardDocument) {
        self.document = document
    }

    func checkpoint() {
        undoStack.append(document)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        document = last
    }
}

/// The drawing surface. Maps the view to the fixed page canvas (aspect fit).
final class WhiteboardCanvasView: NSView {
    var model: WhiteboardModel?
    var onChange: (() -> Void)?
    private var activeStroke: WhiteboardStroke?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var pageRect: CGRect {
        WhiteboardRenderer.aspectFit(WhiteboardDocument.canvasSize, in: bounds.insetBy(dx: 12, dy: 12))
    }

    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let rect = pageRect
        let scale = WhiteboardDocument.canvasSize.width / rect.width
        return CGPoint(x: (p.x - rect.minX) * scale, y: (p.y - rect.minY) * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let model, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = pageRect
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 10, color: CGColor(gray: 0, alpha: 0.25))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.restoreGState()

        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        let scale = rect.width / WhiteboardDocument.canvasSize.width
        context.scaleBy(x: scale, y: scale)
        var page = model.document.currentPage
        if let activeStroke { page.strokes.append(activeStroke) }
        WhiteboardRenderer.draw(page, in: context)
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        window?.makeFirstResponder(self)
        let point = canvasPoint(event)
        model.checkpoint()
        switch model.tool {
        case .eraser:
            model.document.erase(at: point, radius: 14)
        case .pen, .highlighter:
            let highlighter = model.tool == .highlighter
            activeStroke = WhiteboardStroke(points: [point], color: model.color,
                                            width: highlighter ? max(16, model.width * 4) : model.width,
                                            isHighlighter: highlighter)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let point = canvasPoint(event)
        if model.tool == .eraser {
            model.document.erase(at: point, radius: 14)
        } else {
            activeStroke?.points.append(point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        if let stroke = activeStroke {
            model.document.currentPage.strokes.append(stroke)
            activeStroke = nil
        }
        needsDisplay = true
        onChange?()
    }

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case 123: model.document.go(-1)            // ←
        case 124: model.document.go(1)             // →
        case 6 where command:                      // ⌘Z
            model.undo()
        case 35: model.tool = .pen                 // P
        case 4: model.tool = .highlighter          // H
        case 14: model.tool = .eraser              // E
        default:
            super.keyDown(with: event)
            return
        }
        needsDisplay = true
        onChange?()
    }
}

struct WhiteboardCanvas: NSViewRepresentable {
    @ObservedObject var model: WhiteboardModel
    let onChange: () -> Void

    func makeNSView(context: Context) -> WhiteboardCanvasView {
        let view = WhiteboardCanvasView()
        view.model = model
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: WhiteboardCanvasView, context: Context) {
        view.model = model
        view.needsDisplay = true
    }
}

struct WhiteboardView: View {
    @ObservedObject var model: WhiteboardModel
    let onChange: () -> Void
    let onInsertScreenshot: () -> Void
    let onExportPDF: () -> Void
    let onExportPNG: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            WhiteboardCanvas(model: model, onChange: onChange)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.tool) {
                Image(systemName: "pencil.tip").tag(WhiteboardTool.pen)
                Image(systemName: "highlighter").tag(WhiteboardTool.highlighter)
                Image(systemName: "eraser").tag(WhiteboardTool.eraser)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .help(L10n.t("Pen (P) · Highlighter (H) · Eraser (E)", "畫筆（P）· 螢光筆（H）· 橡皮擦（E）"))

            HStack(spacing: 6) {
                ForEach(Array(WhiteboardColor.palette.enumerated()), id: \.offset) { _, color in
                    Button {
                        model.color = color
                        if model.tool == .eraser { model.tool = .pen }
                    } label: {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(model.color == color ? 0.9 : 0.2),
                                                           lineWidth: model.color == color ? 2.5 : 1))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
            }

            Slider(value: $model.width, in: 1...16, step: 1)
                .frame(width: 90)
                .help(L10n.t("Line width", "線條粗細"))

            Picker("", selection: Binding(
                get: { model.document.currentPage.background },
                set: { value in
                    model.checkpoint()
                    model.document.currentPage.background = value
                    onChange()
                }
            )) {
                ForEach(WhiteboardBackground.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(width: 100)

            Spacer(minLength: 8)

            Button { model.document.go(-1); onChange() } label: { Image(systemName: "chevron.left") }
                .disabled(model.document.currentIndex == 0)
            Text("\(model.document.currentIndex + 1) / \(model.document.pages.count)")
                .monospacedDigit()
                .frame(minWidth: 52)
            Button { model.document.go(1); onChange() } label: { Image(systemName: "chevron.right") }
                .disabled(model.document.currentIndex >= model.document.pages.count - 1)

            Menu {
                Button(L10n.t("New Page", "新增頁面")) { model.checkpoint(); model.document.addPage(); onChange() }
                Button(L10n.t("Insert Screenshot as New Page", "插入螢幕截圖為新頁面")) { onInsertScreenshot() }
                Button(L10n.t("Clear Page", "清除本頁")) {
                    model.checkpoint()
                    model.document.currentPage.strokes = []
                    model.document.currentPage.imagePNG = nil
                    onChange()
                }
                Button(L10n.t("Delete Page", "刪除本頁")) { model.checkpoint(); model.document.deleteCurrentPage(); onChange() }
                Divider()
                Button(L10n.t("Undo", "復原")) { model.undo(); onChange() }
                Divider()
                Button(L10n.t("Export All Pages as PDF…", "匯出全部頁面為 PDF…")) { onExportPDF() }
                Button(L10n.t("Export This Page as PNG…", "匯出本頁為 PNG…")) { onExportPNG() }
            } label: {
                Label(L10n.t("Pages", "頁面"), systemImage: "doc.on.doc")
            }
            .fixedSize()
        }
    }
}

/// The whiteboard window (Control+Shift+W).
@MainActor
final class WhiteboardController: NSObject, NSWindowDelegate {
    private let store: WhiteboardStore
    private let model: WhiteboardModel
    private var window: NSWindow?
    private var saveTask: Task<Void, Never>?

    init(store: WhiteboardStore = WhiteboardStore()) {
        self.store = store
        self.model = WhiteboardModel(document: store.load())
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    @objc func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
            saveNow()
        } else {
            show()
        }
    }

    func show() {
        if window == nil {
            let view = WhiteboardView(
                model: model,
                onChange: { [weak self] in self?.scheduleSave() },
                onInsertScreenshot: { [weak self] in self?.insertScreenshot() },
                onExportPDF: { [weak self] in self?.exportPDF() },
                onExportPNG: { [weak self] in self?.exportPNG() }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.t("TeachLens Whiteboard", "TeachLens 白板")
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        saveNow()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        store.save(model.document)
    }

    private func insertScreenshot() {
        let window = self.window
        window?.orderOut(nil)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            let displayID = CGMainDisplayID()
            let image = CGDisplayCreateImage(displayID)
            window?.makeKeyAndOrderFront(nil)
            guard let self else { return }
            guard let image,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                let alert = NSAlert()
                alert.messageText = L10n.t("Couldn’t capture the screen", "無法擷取螢幕")
                alert.informativeText = L10n.t("Allow Screen Recording for TeachLens in System Settings, then reopen TeachLens.",
                                               "請在系統設定開啟 TeachLens 的「螢幕錄製」權限，再重新打開 TeachLens。")
                alert.runModal()
                return
            }
            self.model.checkpoint()
            self.model.document.addPage(after: .white)
            self.model.document.currentPage.imagePNG = png
            self.scheduleSave()
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = L10n.t("TeachLens Whiteboard.pdf", "TeachLens 白板.pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? WhiteboardRenderer.pdfData(model.document).write(to: url)
    }

    private func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = L10n.t("TeachLens Whiteboard Page \(model.document.currentIndex + 1).png",
                                            "TeachLens 白板 第\(model.document.currentIndex + 1)頁.png")
        guard panel.runModal() == .OK, let url = panel.url,
              let data = WhiteboardRenderer.pngData(model.document.currentPage, scale: 2) else { return }
        try? data.write(to: url)
    }
}
