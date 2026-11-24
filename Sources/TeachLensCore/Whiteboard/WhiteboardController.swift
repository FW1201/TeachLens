import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WhiteboardTool: String, CaseIterable, Sendable {
    case pen, highlighter, laser, eraser
    case line, arrow, rectangle, text

    /// The drawing tools on the bar; shapes and text sit in one menu.
    static let barTools: [WhiteboardTool] = [.pen, .highlighter, .laser]
    static let shapeTools: [WhiteboardTool] = [.line, .arrow, .rectangle, .text]

    var isShape: Bool { Self.shapeTools.contains(self) }

    var title: String {
        switch self {
        case .pen: return L10n.t("Pen", "畫筆")
        case .highlighter: return L10n.t("Highlighter", "螢光筆")
        case .laser: return L10n.t("Laser Pointer", "雷射筆")
        case .eraser: return L10n.t("Eraser", "橡皮擦")
        case .line: return L10n.t("Line", "直線")
        case .arrow: return L10n.t("Arrow", "箭頭")
        case .rectangle: return L10n.t("Box", "方框")
        case .text: return L10n.t("Text", "文字")
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .laser: return "wand.and.rays"
        case .eraser: return "eraser"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        }
    }

    var key: String? {
        switch self {
        case .pen: return "P"
        case .highlighter: return "H"
        case .laser: return "L"
        case .eraser: return "E"
        case .arrow: return "A"
        case .text: return "T"
        default: return nil
        }
    }

    var strokeKind: WhiteboardStrokeKind {
        switch self {
        case .line: return .line
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .text: return .text
        default: return .free
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
final class WhiteboardCanvasView: NSView, NSTextFieldDelegate {
    var model: WhiteboardModel?
    var onChange: (() -> Void)?
    private var activeStroke: WhiteboardStroke?
    private var cachedPage: WhiteboardPage?
    private var cachedPixelSize: CGSize = .zero
    private var cachedImage: CGImage?

    /// Laser trails: points with the time they were drawn. They fade and are
    /// never saved.
    private var laserTrails: [[(point: CGPoint, time: TimeInterval)]] = []
    private var laserTimer: Timer?
    static let laserLife: TimeInterval = 1.2

    /// The text box being typed into, and where (canvas coordinates).
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero

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

    private var canvasScale: CGFloat { pageRect.width / WhiteboardDocument.canvasSize.width }

    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let rect = pageRect
        let scale = WhiteboardDocument.canvasSize.width / rect.width
        return CGPoint(x: (p.x - rect.minX) * scale, y: (p.y - rect.minY) * scale)
    }

    private func viewPoint(_ canvas: CGPoint) -> CGPoint {
        let rect = pageRect
        return CGPoint(x: rect.minX + canvas.x * canvasScale, y: rect.minY + canvas.y * canvasScale)
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
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: canvasScale, y: canvasScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if let activeStroke {
            WhiteboardRenderer.stroke(activeStroke, in: context)
        }
        drawLaser(in: context)
        context.restoreGState()
    }

    // MARK: Laser

    private func drawLaser(in context: CGContext) {
        guard !laserTrails.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for trail in laserTrails {
            for (a, b) in zip(trail, trail.dropFirst()) {
                let age = now - b.time
                guard age < Self.laserLife else { continue }
                let alpha = CGFloat(1 - age / Self.laserLife)
                context.setStrokeColor(CGColor(red: 1, green: 0.15, blue: 0.2, alpha: alpha * 0.35))
                context.setLineWidth(16)
                context.strokeLineSegments(between: [a.point, b.point])
                context.setStrokeColor(CGColor(red: 1, green: 0.15, blue: 0.2, alpha: alpha))
                context.setLineWidth(6)
                context.strokeLineSegments(between: [a.point, b.point])
            }
        }
    }

    private func startLaserTimer() {
        guard laserTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.laserTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        laserTimer = timer
    }

    private func laserTick() {
        let now = ProcessInfo.processInfo.systemUptime
        laserTrails = laserTrails
            .map { trail in trail.filter { now - $0.time < Self.laserLife } }
            .filter { !$0.isEmpty }
        needsDisplay = true
        if laserTrails.isEmpty {
            laserTimer?.invalidate()
            laserTimer = nil
        }
    }

    // MARK: Text

    private func beginText(at canvas: CGPoint) {
        commitText()
        guard let model else { return }
        textOrigin = canvas
        let probe = WhiteboardStroke(points: [canvas], color: model.color, width: model.width, isHighlighter: false,
                                     kind: .text, text: "")
        let fontSize = probe.fontSize * canvasScale
        let origin = viewPoint(canvas)
        let field = NSTextField(frame: NSRect(x: origin.x - 4, y: origin.y - 2, width: 320, height: fontSize * 1.5))
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = NSColor(cgColor: model.color.cgColor) ?? .black
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        field.focusRingType = .exterior
        field.placeholderString = L10n.t("Type, then press Return", "輸入文字後按 Return")
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    /// Adds the typed text to the page (empty text adds nothing).
    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        guard let model, !text.isEmpty else { return }
        model.checkpoint()
        model.document.currentPage.strokes.append(
            WhiteboardStroke(points: [textOrigin], color: model.color, width: model.width, isHighlighter: false,
                             kind: .text, text: text))
        needsDisplay = true
        onChange?()
        window?.makeFirstResponder(self)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitText()
            return true
        }
        return false
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        commitText()
        window?.makeFirstResponder(self)
        let point = canvasPoint(event)
        switch model.tool {
        case .laser:
            laserTrails.append([(point, ProcessInfo.processInfo.systemUptime)])
            startLaserTimer()
            return
        case .text:
            beginText(at: point)
            return
        default:
            break
        }
        model.checkpoint()
        switch model.tool {
        case .eraser:
            model.document.erase(at: point, radius: Self.eraserRadius)
        case .line, .arrow, .rectangle:
            activeStroke = WhiteboardStroke(points: [point, point], color: model.color, width: model.width,
                                            isHighlighter: false, kind: model.tool.strokeKind)
        case .pen, .highlighter:
            let highlighter = model.tool == .highlighter
            activeStroke = WhiteboardStroke(points: [point], color: model.color,
                                            width: highlighter ? max(16, model.width * 4) : model.width,
                                            isHighlighter: highlighter)
        case .laser, .text:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let point = canvasPoint(event)
        switch model.tool {
        case .eraser:
            model.document.erase(at: point, radius: Self.eraserRadius)
            needsDisplay = true
        case .laser:
            guard !laserTrails.isEmpty else { return }
            laserTrails[laserTrails.count - 1].append((point, ProcessInfo.processInfo.systemUptime))
            needsDisplay = true
        case .line, .arrow, .rectangle:
            guard var stroke = activeStroke else { return }
            stroke.points[stroke.points.count - 1] = point
            activeStroke = stroke
            needsDisplay = true
        case .pen, .highlighter:
            guard var stroke = activeStroke else { return }
            // Skip sub-pixel moves: high-rate trackpads send many, and every
            // point costs memory, save time and drawing time later.
            if let last = stroke.points.last,
               hypot(point.x - last.x, point.y - last.y) < Self.minimumPointSpacing { return }
            stroke.points.append(point)
            activeStroke = stroke
            needsDisplay = true
        case .text:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model, model.tool != .laser, model.tool != .text else { return }
        if let stroke = activeStroke {
            let first = stroke.points.first ?? .zero, last = stroke.points.last ?? .zero
            // A shape needs a real drag; a click without one adds nothing.
            if stroke.kind == .free || hypot(last.x - first.x, last.y - first.y) > 3 {
                model.document.currentPage.strokes.append(stroke)
            } else {
                model.discardCheckpointIfUnchanged()
            }
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
        case 37: model.tool = .laser               // L
        case 14: model.tool = .eraser              // E
        case 0: model.tool = .arrow                // A
        case 17: model.tool = .text                // T
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
    let onToggleFullScreen: () -> Void

    @State private var showingPages = false

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

    private func toolHelp(_ tool: WhiteboardTool) -> String {
        tool.key.map { "\(tool.title)（\($0)）" } ?? tool.title
    }

    private func toolButton(_ tool: WhiteboardTool, index: Int) -> some View {
        Button { model.tool = tool } label: { Image(systemName: tool.symbol) }
            .buttonStyle(ChromeIconButtonStyle(isOn: model.tool == tool, tint: tool == .laser ? .red : .accentColor))
            .help(toolHelp(tool))
            .accessibilityLabel(tool.title)
            .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
            .staggered(index)
    }

    private var shapesMenu: some View {
        let current = model.tool.isShape ? model.tool : nil
        return Menu {
            ForEach(WhiteboardTool.shapeTools, id: \.self) { tool in
                Button { model.tool = tool } label: {
                    Label(toolHelp(tool), systemImage: tool == current ? "checkmark" : tool.symbol)
                }
            }
        } label: {
            Image(systemName: current?.symbol ?? "square.on.circle")
        }
        .menuStyle(.button)
        .buttonStyle(ChromeIconButtonStyle(isOn: current != nil))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.t("Shapes and text", "形狀與文字"))
        .accessibilityLabel(L10n.t("Shapes and text", "形狀與文字"))
    }

    private var toolBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(WhiteboardTool.barTools.enumerated()), id: \.element) { index, tool in
                toolButton(tool, index: index)
            }
            shapesMenu.staggered(3)
            toolButton(.eraser, index: 4)

            ChromeDivider()

            HStack(spacing: 5) {
                ForEach(Array(WhiteboardColor.palette.enumerated()), id: \.offset) { index, color in
                    swatch(color, index: index)
                }
            }
            .opacity(model.tool == .eraser || model.tool == .laser ? 0.45 : 1)

            ChromeDivider()

            widthMenu.staggered(12)
            backgroundMenu.staggered(13)

            ChromeDivider()

            Button { model.undo(); onChange() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ChromeIconButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
                .help(L10n.t("Undo (⌘Z)", "復原（⌘Z）"))
                .accessibilityLabel(L10n.t("Undo", "復原"))
                .staggered(14)
            Button(action: onInsertScreenshot) { Image(systemName: "camera.viewfinder") }
                .buttonStyle(ChromeIconButtonStyle())
                .help(L10n.t("Insert Screenshot as New Page", "插入螢幕截圖為新頁面"))
                .accessibilityLabel(L10n.t("Insert Screenshot", "插入螢幕截圖"))
                .staggered(15)
            Button(action: onToggleFullScreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(ChromeIconButtonStyle())
                .keyboardShortcut("f", modifiers: [.control, .command])
                .help(L10n.t("Full Screen (⌃⌘F)", "全螢幕（⌃⌘F）"))
                .accessibilityLabel(L10n.t("Full Screen", "全螢幕"))
                .staggered(16)
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
            .staggered(17)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .chromeSurface(Capsule())
    }

    private func swatch(_ color: WhiteboardColor, index: Int) -> some View {
        let selected = model.color == color && model.tool != .eraser && model.tool != .laser
        return Button {
            model.color = color
            if model.tool == .eraser || model.tool == .laser { model.tool = .pen }
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
        .staggered(5 + index)
    }

    private var widthMenu: some View {
        Menu {
            ForEach(WhiteboardModel.widths, id: \.self) { width in
                Button {
                    model.width = width
                    if model.tool == .eraser || model.tool == .laser { model.tool = .pen }
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
        .help(L10n.t("Line width and text size", "線條粗細與文字大小"))
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
            Button { showingPages.toggle() } label: {
                Text("\(document.currentIndex + 1) / \(document.pages.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: document.currentIndex)
                    .frame(minWidth: 52, minHeight: TeachLensChrome.iconHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("Show all pages", "顯示所有頁面"))
            .accessibilityLabel(L10n.t("Page \(document.currentIndex + 1) of \(document.pages.count)",
                                       "第 \(document.currentIndex + 1) 頁，共 \(document.pages.count) 頁"))
            .popover(isPresented: $showingPages, arrowEdge: .top) {
                WhiteboardPagesView(model: model, onChange: onChange) { showingPages = false }
            }
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

/// Page thumbnails: click to jump, right-click to move a page.
private struct WhiteboardPagesView: View {
    @ObservedObject var model: WhiteboardModel
    let onChange: () -> Void
    let dismiss: () -> Void
    @State private var thumbnails: [NSImage] = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                    let current = index == model.document.currentIndex
                    Button {
                        model.document.currentIndex = index
                        onChange()
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(16 / 10, contentMode: .fit)
                                .frame(width: 128)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(current ? Color.accentColor : Color.primary.opacity(0.15),
                                                  lineWidth: current ? 2.5 : 1))
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(current ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { move(index, by: -1) } label: {
                            Label(L10n.t("Move Earlier", "往前移"), systemImage: "arrow.left")
                        }
                        .disabled(index == 0)
                        Button { move(index, by: 1) } label: {
                            Label(L10n.t("Move Later", "往後移"), systemImage: "arrow.right")
                        }
                        .disabled(index >= thumbnails.count - 1)
                    }
                    .accessibilityLabel(L10n.t("Page \(index + 1)", "第 \(index + 1) 頁"))
                }
            }
            .padding(14)
        }
        .frame(maxWidth: 620)
        .onAppear(perform: render)
    }

    private func move(_ index: Int, by delta: Int) {
        model.checkpoint()
        model.document.movePage(from: index, by: delta)
        onChange()
        render()
    }

    /// Small renders of every page, made when the popover opens.
    private func render() {
        thumbnails = model.document.pages.map { page in
            guard let image = WhiteboardRenderer.thumbnail(page) else {
                return NSImage(size: NSSize(width: 256, height: 160))
            }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
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
                onExportPNG: { [weak self] in self?.exportPNG() },
                onToggleFullScreen: { [weak self] in self?.window?.toggleFullScreen(nil) }
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
        showSharingTipOnce()
    }

    /// The whiteboard is its own window: if the class only sees a shared
    /// window (e.g. the slides), students won't see it. Say so the first time.
    private func showSharingTipOnce() {
        let key = "whiteboardSharingTipShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        GlassToast.shared.show(
            symbol: "rectangle.on.rectangle",
            title: L10n.t("Students see the whiteboard only if you share it", "學生要看到白板，需分享它"),
            message: L10n.t("Share your entire screen, or share the whiteboard window. ⌃⌘F makes it full screen.",
                            "請分享整個螢幕，或在會議軟體改分享白板視窗；⌃⌘F 可切換全螢幕。"),
            duration: 6)
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
