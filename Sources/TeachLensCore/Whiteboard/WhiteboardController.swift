import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WhiteboardTool: String, CaseIterable, Sendable {
    case pen, highlighter, eraser

    var title: String {
        switch self {
        case .pen: return L10n.t("Pen", "畫筆")
        case .highlighter: return L10n.t("Highlighter", "螢光筆")
        case .eraser: return L10n.t("Eraser", "橡皮擦")
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var key: String {
        switch self {
        case .pen: return "P"
        case .highlighter: return "H"
        case .eraser: return "E"
        }
    }
}

@MainActor
final class WhiteboardModel: ObservableObject {
    @Published var document: WhiteboardDocument
    @Published var tool: WhiteboardTool = .pen
    @Published var color: WhiteboardColor = WhiteboardColor.palette[0]
    @Published var width: Double = 4
    @Published private(set) var canUndo = false
    private var undoStack: [WhiteboardDocument] = []

    static let widths: [Double] = [2, 4, 8, 12]

    init(document: WhiteboardDocument) {
        self.document = document
    }

    func checkpoint() {
        undoStack.append(document)
        if undoStack.count > 100 { undoStack.removeFirst() }
        if !canUndo { canUndo = true }
    }

    /// Drops the checkpoint taken for a gesture that changed nothing (an eraser
    /// tap that missed every stroke), so Undo isn't spent on a no-op.
    func discardCheckpointIfUnchanged() {
        guard let last = undoStack.last, last == document else { return }
        undoStack.removeLast()
        canUndo = !undoStack.isEmpty
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        document = last
        canUndo = !undoStack.isEmpty
    }
}

/// The drawing surface. Maps the view to the fixed page canvas (aspect fit).
///
/// Performance: the page (background, screenshot and finished strokes) is
/// rendered once into a bitmap at the view's pixel size and reused, so a drag
/// only draws that bitmap plus the stroke in progress instead of decoding the
/// screenshot and re-stroking every line on every mouse event.
final class WhiteboardCanvasView: NSView {
    var model: WhiteboardModel?
    var onChange: (() -> Void)?
    private var activeStroke: WhiteboardStroke?
    private var cachedPage: WhiteboardPage?
    private var cachedPixelSize: CGSize = .zero
    private var cachedImage: CGImage?

    /// Room kept around the page for the floating toolbars.
    static let insets = NSEdgeInsets(top: 66, left: 28, bottom: 62, right: 28)
    /// Pointer moves shorter than this (canvas points) don't add a point.
    static let minimumPointSpacing: CGFloat = 1.2
    static let eraserRadius: Double = 14

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var pageRect: CGRect {
        let i = Self.insets
        let area = CGRect(x: bounds.minX + i.left, y: bounds.minY + i.top,
                          width: max(1, bounds.width - i.left - i.right),
                          height: max(1, bounds.height - i.top - i.bottom))
        return WhiteboardRenderer.aspectFit(WhiteboardDocument.canvasSize, in: area).integral
    }

    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let rect = pageRect
        let scale = WhiteboardDocument.canvasSize.width / rect.width
        return CGPoint(x: (p.x - rect.minX) * scale, y: (p.y - rect.minY) * scale)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        cachedImage = nil
        needsDisplay = true
    }

    private func pageImage(_ page: WhiteboardPage, pixelSize: CGSize) -> CGImage? {
        if let cachedImage, cachedPixelSize == pixelSize, cachedPage == page { return cachedImage }
        let width = Int(pixelSize.width), height = Int(pixelSize.height)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / WhiteboardDocument.canvasSize.width,
                        y: -CGFloat(height) / WhiteboardDocument.canvasSize.height)
        WhiteboardRenderer.draw(page, in: context)
        cachedImage = context.makeImage()
        cachedPage = page
        cachedPixelSize = pixelSize
        return cachedImage
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
        guard let model, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = pageRect
        let backing = window?.backingScaleFactor ?? 2

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 3), blur: 14, color: CGColor(gray: 0, alpha: 0.22))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.clip()
        if let image = pageImage(model.document.currentPage,
                                 pixelSize: CGSize(width: rect.width * backing, height: rect.height * backing)) {
            // The bitmap is upright; flip locally because this view is flipped.
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        }
        if let activeStroke {
            context.translateBy(x: rect.minX, y: rect.minY)
            let scale = rect.width / WhiteboardDocument.canvasSize.width
            context.scaleBy(x: scale, y: scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            WhiteboardRenderer.stroke(activeStroke, in: context)
        }
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        window?.makeFirstResponder(self)
        let point = canvasPoint(event)
        model.checkpoint()
        switch model.tool {
        case .eraser:
            model.document.erase(at: point, radius: Self.eraserRadius)
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
            model.document.erase(at: point, radius: Self.eraserRadius)
            needsDisplay = true
        } else if var stroke = activeStroke {
            // Skip sub-pixel moves: high-rate trackpads send many, and every
            // point costs memory, save time and drawing time later.
            if let last = stroke.points.last,
               hypot(point.x - last.x, point.y - last.y) < Self.minimumPointSpacing { return }
            stroke.points.append(point)
            activeStroke = stroke
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        if let stroke = activeStroke {
            model.document.currentPage.strokes.append(stroke)
            activeStroke = nil
        } else {
            model.discardCheckpointIfUnchanged()
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

/// The whiteboard window's content: the page fills the window and two
/// floating glass bars carry the controls, matching Graphical Mode.
struct WhiteboardView: View {
    @ObservedObject var model: WhiteboardModel
    let onChange: () -> Void
    let onInsertScreenshot: () -> Void
    let onExportPDF: () -> Void
    let onExportPNG: () -> Void

    var body: some View {
        ZStack {
            WhiteboardCanvas(model: model, onChange: onChange)
            VStack {
                toolBar
                Spacer(minLength: 0)
                pageBar
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    // MARK: Tool bar

    private var toolBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(WhiteboardTool.allCases.enumerated()), id: \.element) { index, tool in
                Button { model.tool = tool } label: { Image(systemName: tool.symbol) }
                    .buttonStyle(ChromeIconButtonStyle(isOn: model.tool == tool))
                    .help("\(tool.title)（\(tool.key)）")
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
                    .staggered(index)
            }

            ChromeDivider()

            HStack(spacing: 5) {
                ForEach(Array(WhiteboardColor.palette.enumerated()), id: \.offset) { index, color in
                    swatch(color, index: index)
                }
            }
            .opacity(model.tool == .eraser ? 0.45 : 1)

            ChromeDivider()

            widthMenu.staggered(10)
            backgroundMenu.staggered(11)

            ChromeDivider()

            Button { model.undo(); onChange() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ChromeIconButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
                .help(L10n.t("Undo (⌘Z)", "復原（⌘Z）"))
                .accessibilityLabel(L10n.t("Undo", "復原"))
                .staggered(12)
            Button(action: onInsertScreenshot) { Image(systemName: "camera.viewfinder") }
                .buttonStyle(ChromeIconButtonStyle())
                .help(L10n.t("Insert Screenshot as New Page", "插入螢幕截圖為新頁面"))
                .accessibilityLabel(L10n.t("Insert Screenshot", "插入螢幕截圖"))
                .staggered(13)
            Menu {
                Button(action: onExportPDF) {
                    Label(L10n.t("Export All Pages as PDF…", "匯出全部頁面為 PDF…"), systemImage: "doc.richtext")
                }
                Button(action: onExportPNG) {
                    Label(L10n.t("Export This Page as PNG…", "匯出本頁為 PNG…"), systemImage: "photo")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .chromeIconMenu()
            .help(L10n.t("Export", "匯出"))
            .accessibilityLabel(L10n.t("Export", "匯出"))
            .staggered(14)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .chromeSurface(Capsule())
    }

    private func swatch(_ color: WhiteboardColor, index: Int) -> some View {
        let selected = model.color == color && model.tool != .eraser
        return Button {
            model.color = color
            if model.tool == .eraser { model.tool = .pen }
        } label: {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                .scaleEffect(selected ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: selected)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .staggered(3 + index)
    }

    private var widthMenu: some View {
        Menu {
            ForEach(WhiteboardModel.widths, id: \.self) { width in
                Button {
                    model.width = width
                    if model.tool == .eraser { model.tool = .pen }
                } label: {
                    if model.width == width {
                        Label(Self.widthTitle(width), systemImage: "checkmark")
                    } else {
                        Text(Self.widthTitle(width))
                    }
                }
            }
        } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: 4 + model.width, height: 4 + model.width)
                .frame(width: 18, height: 18)
        }
        .chromeIconMenu()
        .help(L10n.t("Line width", "線條粗細"))
        .accessibilityLabel(L10n.t("Line width", "線條粗細"))
        .accessibilityValue(Self.widthTitle(model.width))
    }

    static func widthTitle(_ width: Double) -> String {
        switch width {
        case ..<3: return L10n.t("Fine", "細")
        case ..<6: return L10n.t("Medium", "中")
        case ..<10: return L10n.t("Bold", "粗")
        default: return L10n.t("Extra Bold", "特粗")
        }
    }

    private var backgroundMenu: some View {
        let current = model.document.currentPage.background
        return Menu {
            ForEach(WhiteboardBackground.allCases, id: \.self) { background in
                Button {
                    guard background != model.document.currentPage.background else { return }
                    model.checkpoint()
                    model.document.currentPage.background = background
                    onChange()
                } label: {
                    Label(background.title, systemImage: background == current ? "checkmark" : background.symbol)
                }
            }
        } label: {
            Image(systemName: current.symbol)
        }
        .chromeIconMenu()
        .help(L10n.t("Background", "背景"))
        .accessibilityLabel(L10n.t("Background", "背景"))
        .accessibilityValue(current.title)
    }

    // MARK: Page bar

    private var pageBar: some View {
        let document = model.document
        return HStack(spacing: 4) {
            Button { model.document.go(-1); onChange() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(ChromeIconButtonStyle())
                .disabled(document.currentIndex == 0)
                .help(L10n.t("Previous Page (←)", "上一頁（←）"))
                .accessibilityLabel(L10n.t("Previous Page", "上一頁"))
            Text("\(document.currentIndex + 1) / \(document.pages.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: document.currentIndex)
                .frame(minWidth: 52)
                .accessibilityLabel(L10n.t("Page \(document.currentIndex + 1) of \(document.pages.count)",
                                           "第 \(document.currentIndex + 1) 頁，共 \(document.pages.count) 頁"))
            Button { model.document.go(1); onChange() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(ChromeIconButtonStyle())
                .disabled(document.currentIndex >= document.pages.count - 1)
                .help(L10n.t("Next Page (→)", "下一頁（→）"))
                .accessibilityLabel(L10n.t("Next Page", "下一頁"))

            ChromeDivider()

            Button { model.checkpoint(); model.document.addPage(); onChange() } label: { Image(systemName: "plus") }
                .buttonStyle(ChromeIconButtonStyle())
                .help(L10n.t("New Page", "新增頁面"))
                .accessibilityLabel(L10n.t("New Page", "新增頁面"))
            Menu {
                Button {
                    model.checkpoint()
                    model.document.currentPage.strokes = []
                    model.document.currentPage.imagePNG = nil
                    onChange()
                } label: {
                    Label(L10n.t("Clear Page", "清除本頁"), systemImage: "xmark.square")
                }
                Button(role: .destructive) {
                    model.checkpoint(); model.document.deleteCurrentPage(); onChange()
                } label: {
                    Label(L10n.t("Delete Page", "刪除本頁"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .chromeIconMenu()
            .help(L10n.t("Page Options", "頁面選項"))
            .accessibilityLabel(L10n.t("Page Options", "頁面選項"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .chromeSurface(Capsule())
    }
}

/// The whiteboard window (Control+Shift+W).
@MainActor
final class WhiteboardController: NSObject, NSWindowDelegate {
    private let store: WhiteboardStore
    private let model: WhiteboardModel
    private var window: NSWindow?
    private var saveTask: Task<Void, Never>?
    /// Encoding a page with a screenshot is megabytes of JSON; do it off the
    /// main thread, one save at a time, so drawing never stutters.
    private let saveQueue = DispatchQueue(label: "io.github.fw1201.teachlens.whiteboard-save", qos: .utility)
    private var terminateObserver: NSObjectProtocol?

    /// Screenshots are scaled down to this width before they are stored: twice
    /// the page width is sharp in PDF and PNG exports and keeps saves small.
    static let maxScreenshotWidth = Int(WhiteboardDocument.canvasSize.width * 2)

    init(store: WhiteboardStore = WhiteboardStore()) {
        self.store = store
        self.model = WhiteboardModel(document: store.load())
        super.init()
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSynchronously() }
        }
    }

    var isVisible: Bool { window?.isVisible ?? false }
    var pageCount: Int { model.document.pages.count }
    var saveLocation: URL { store.url }

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
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .underPageBackgroundColor
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            _ = window.setFrameAutosaveName("TeachLensWhiteboard")
            window.delegate = self
            if !window.setFrameUsingName("TeachLensWhiteboard") {
                window.center()
            }
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
        saveTask?.cancel()
        let document = model.document
        let store = self.store
        saveQueue.async { store.save(document) }
    }

    /// At quit, write the latest document and wait for queued saves.
    private func saveSynchronously() {
        saveTask?.cancel()
        let document = model.document
        let store = self.store
        saveQueue.sync { store.save(document) }
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
                  let png = Self.storablePNG(image) else {
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

    /// PNG data for a screenshot, scaled down to `maxScreenshotWidth`.
    static func storablePNG(_ image: CGImage) -> Data? {
        var output = image
        if image.width > maxScreenshotWidth {
            let width = maxScreenshotWidth
            let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
            if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                if let scaled = context.makeImage() { output = scaled }
            }
        }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = L10n.t("TeachLens Whiteboard.pdf", "TeachLens 白板.pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try WhiteboardRenderer.pdfData(model.document).write(to: url)
            ExportFeedback.saved(url)
        } catch {
            ExportFeedback.failed(error)
        }
    }

    func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = L10n.t("TeachLens Whiteboard Page \(model.document.currentIndex + 1).png",
                                            "TeachLens 白板 第\(model.document.currentIndex + 1)頁.png")
        guard panel.runModal() == .OK, let url = panel.url,
              let data = WhiteboardRenderer.pngData(model.document.currentPage, scale: 2) else { return }
        do {
            try data.write(to: url)
            ExportFeedback.saved(url)
        } catch {
            ExportFeedback.failed(error)
        }
    }
}
