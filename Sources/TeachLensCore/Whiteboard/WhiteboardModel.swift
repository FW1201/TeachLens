import AppKit
import CoreGraphics
import ImageIO
import CoreText

/// Multi-page whiteboard data. Pages use a fixed 16:10 canvas (1600 × 1000
/// points, top-left origin) so exports look the same at any window size.
enum WhiteboardBackground: String, Codable, CaseIterable, Sendable {
    case white, black, grid, lines

    var title: String {
        switch self {
        case .white: return L10n.t("White", "白板")
        case .black: return L10n.t("Black", "黑板")
        case .grid: return L10n.t("Grid", "方格")
        case .lines: return L10n.t("Lines", "橫線")
        }
    }

    var symbol: String {
        switch self {
        case .white: return "square"
        case .black: return "square.fill"
        case .grid: return "squareshape.split.3x3"
        case .lines: return "line.3.horizontal"
        }
    }
}

struct WhiteboardColor: Codable, Equatable, Sendable {
    var r: Double, g: Double, b: Double

    var cgColor: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }

    /// Spoken name, for VoiceOver.
    var title: String {
        let names = [
            L10n.t("Black", "黑"), L10n.t("Red", "紅"), L10n.t("Blue", "藍"), L10n.t("Green", "綠"),
            L10n.t("Orange", "橘"), L10n.t("Gold", "金"), L10n.t("White", "白"),
        ]
        guard let index = Self.palette.firstIndex(of: self), index < names.count else { return L10n.t("Color", "顏色") }
        return names[index]
    }

    static let palette: [WhiteboardColor] = [
        WhiteboardColor(r: 0.10, g: 0.10, b: 0.12), WhiteboardColor(r: 0.93, g: 0.20, b: 0.20),
        WhiteboardColor(r: 0.12, g: 0.45, b: 0.95), WhiteboardColor(r: 0.10, g: 0.66, b: 0.35),
        WhiteboardColor(r: 0.98, g: 0.62, b: 0.05), WhiteboardColor(r: 0.85, g: 0.69, b: 0.24),
        WhiteboardColor(r: 1, g: 1, b: 1),
    ]
}

/// What a stroke draws. `free` is a hand-drawn line; the shapes use the first
/// and last point; text draws `text` at the first point.
enum WhiteboardStrokeKind: String, Codable, Sendable {
    case free, line, arrow, rectangle, text
}

struct WhiteboardStroke: Codable, Equatable, Sendable {
    var points: [CGPoint]
    var color: WhiteboardColor
    var width: Double
    var isHighlighter: Bool
    var kind: WhiteboardStrokeKind = .free
    var text: String?

    init(points: [CGPoint], color: WhiteboardColor, width: Double, isHighlighter: Bool,
         kind: WhiteboardStrokeKind = .free, text: String? = nil) {
        self.points = points
        self.color = color
        self.width = width
        self.isHighlighter = isHighlighter
        self.kind = kind
        self.text = text
    }

    private enum CodingKeys: String, CodingKey { case points, color, width, isHighlighter, kind, text }

    /// Boards saved before shapes existed have no `kind`; they load as free strokes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode([CGPoint].self, forKey: .points)
        color = try c.decode(WhiteboardColor.self, forKey: .color)
        width = try c.decode(Double.self, forKey: .width)
        isHighlighter = try c.decodeIfPresent(Bool.self, forKey: .isHighlighter) ?? false
        kind = (try? c.decodeIfPresent(WhiteboardStrokeKind.self, forKey: .kind)) ?? .free
        text = try c.decodeIfPresent(String.self, forKey: .text)
    }

    /// Font size for text strokes: grows with the chosen line width.
    var fontSize: CGFloat { CGFloat(18 + width * 4) }

    /// The points the eraser measures against: the outline for shapes, the
    /// box around text, the polyline otherwise.
    var hitOutline: [CGPoint] {
        guard let first = points.first else { return [] }
        let last = points.last ?? first
        switch kind {
        case .free, .line, .arrow:
            return kind == .free ? points : [first, last]
        case .rectangle:
            return [first, CGPoint(x: last.x, y: first.y), last, CGPoint(x: first.x, y: last.y), first]
        case .text:
            let size = WhiteboardRenderer.textSize(self)
            let r = CGRect(origin: first, size: size)
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
                    CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY),
                    CGPoint(x: r.maxX, y: r.maxY)]
        }
    }
}

struct WhiteboardPage: Codable, Equatable, Sendable {
    var background: WhiteboardBackground = .white
    var strokes: [WhiteboardStroke] = []
    /// PNG data of an inserted screenshot, drawn under the strokes.
    var imagePNG: Data?
}

struct WhiteboardDocument: Codable, Equatable, Sendable {
    static let canvasSize = CGSize(width: 1600, height: 1000)
    var pages: [WhiteboardPage] = [WhiteboardPage()]
    var currentIndex = 0

    var currentPage: WhiteboardPage {
        get { pages[min(max(0, currentIndex), pages.count - 1)] }
        set { pages[min(max(0, currentIndex), pages.count - 1)] = newValue }
    }

    mutating func addPage(after background: WhiteboardBackground? = nil) {
        let bg = background ?? currentPage.background
        pages.insert(WhiteboardPage(background: bg), at: currentIndex + 1)
        currentIndex += 1
    }

    mutating func deleteCurrentPage() {
        guard pages.count > 1 else {
            pages = [WhiteboardPage(background: currentPage.background)]
            currentIndex = 0
            return
        }
        pages.remove(at: currentIndex)
        currentIndex = min(currentIndex, pages.count - 1)
    }

    /// Moves a page one or more places earlier (negative) or later, keeping
    /// the same page current.
    mutating func movePage(from index: Int, by delta: Int) {
        let target = min(max(0, index + delta), pages.count - 1)
        guard pages.indices.contains(index), target != index else { return }
        let page = pages.remove(at: index)
        pages.insert(page, at: target)
        if currentIndex == index {
            currentIndex = target
        } else if index < currentIndex, target >= currentIndex {
            currentIndex -= 1
        } else if index > currentIndex, target <= currentIndex {
            currentIndex += 1
        }
    }

    mutating func go(_ delta: Int) {
        currentIndex = min(max(0, currentIndex + delta), pages.count - 1)
    }

    /// Removes strokes that pass within `radius` of `point` on the current page.
    mutating func erase(at point: CGPoint, radius: Double) {
        currentPage.strokes.removeAll { stroke in
            Self.distance(from: point, to: stroke.hitOutline) <= radius + stroke.width / 2
        }
    }

    /// Shortest distance from `point` to the polyline through `points`
    /// (segments, not just vertices, so sparse fast strokes erase too).
    static func distance(from point: CGPoint, to points: [CGPoint]) -> Double {
        guard let first = points.first else { return .infinity }
        var best = hypot(point.x - first.x, point.y - first.y)
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var t = lengthSquared > 0 ? ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared : 0
            t = min(max(t, 0), 1)
            let px = a.x + t * dx, py = a.y + t * dy
            best = min(best, hypot(point.x - px, point.y - py))
        }
        return best
    }
}

enum WhiteboardRenderer {
    /// Draws `page` into `context`, which must use a top-left origin and the
    /// page's canvas coordinates (1600 × 1000).
    static func draw(_ page: WhiteboardPage, in context: CGContext) {
        let size = WhiteboardDocument.canvasSize
        let rect = CGRect(origin: .zero, size: size)
        context.saveGState()
        let dark = page.background == .black
        context.setFillColor(dark ? CGColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)

        switch page.background {
        case .grid:
            context.setStrokeColor(CGColor(red: 0.55, green: 0.65, blue: 0.80, alpha: 0.35))
            context.setLineWidth(1)
            var x: CGFloat = 40
            while x < size.width { context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: size.height)); x += 40 }
            var y: CGFloat = 40
            while y < size.height { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: size.width, y: y)); y += 40 }
            context.strokePath()
        case .lines:
            context.setStrokeColor(CGColor(red: 0.45, green: 0.60, blue: 0.85, alpha: 0.45))
            context.setLineWidth(1.5)
            var y: CGFloat = 80
            while y < size.height { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: size.width, y: y)); y += 56 }
            context.strokePath()
        case .white, .black:
            break
        }

        if let data = page.imagePNG,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let fit = aspectFit(CGSize(width: image.width, height: image.height), in: rect.insetBy(dx: 40, dy: 40))
            context.saveGState()
            // Images draw bottom-up; flip locally inside the image rect.
            context.translateBy(x: fit.minX, y: fit.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: fit.size))
            context.restoreGState()
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in page.strokes {
            self.stroke(stroke, in: context)
        }
        context.restoreGState()
    }

    /// Draws one stroke in canvas coordinates; the caller sets round caps.
    static func stroke(_ stroke: WhiteboardStroke, in context: CGContext) {
        guard let first = stroke.points.first else { return }
        let last = stroke.points.last ?? first
        let color = stroke.color.cgColor.copy(alpha: stroke.isHighlighter ? 0.35 : 1) ?? stroke.color.cgColor
        context.setStrokeColor(color)
        context.setLineWidth(stroke.width)
        context.beginPath()
        switch stroke.kind {
        case .free:
            context.move(to: first)
            if stroke.points.count == 1 {
                context.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            } else {
                context.addLines(between: stroke.points)
            }
            context.strokePath()
        case .line:
            context.addLines(between: [first, last])
            context.strokePath()
        case .arrow:
            context.addLines(between: [first, last])
            let angle: CGFloat = atan2(last.y - first.y, last.x - first.x)
            let head = CGFloat(max(14, stroke.width * 4))
            for side: CGFloat in [-1, 1] {
                let a: CGFloat = angle + .pi - side * .pi / 7
                context.move(to: last)
                context.addLine(to: CGPoint(x: last.x + head * cos(a), y: last.y + head * sin(a)))
            }
            context.strokePath()
        case .rectangle:
            context.addRect(CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                   width: abs(last.x - first.x), height: abs(last.y - first.y)))
            context.strokePath()
        case .text:
            drawText(stroke, in: context, color: color)
        }
    }

    private static func textAttributes(_ stroke: WhiteboardStroke, color: CGColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: stroke.fontSize, weight: .semibold),
         .foregroundColor: NSColor(cgColor: color) ?? .black]
    }

    static func textSize(_ stroke: WhiteboardStroke) -> CGSize {
        let string = NSAttributedString(string: stroke.text ?? "", attributes: textAttributes(stroke, color: stroke.color.cgColor))
        return string.size()
    }

    /// Text in a top-left-origin context: flip locally so glyphs stand upright.
    private static func drawText(_ stroke: WhiteboardStroke, in context: CGContext, color: CGColor) {
        guard let text = stroke.text, !text.isEmpty, let origin = stroke.points.first else { return }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: textAttributes(stroke, color: color)))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func aspectFit(_ content: CGSize, in rect: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0 else { return rect }
        let scale = min(rect.width / content.width, rect.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// A multi-page PDF of the whole document.
    static func pdfData(_ document: WhiteboardDocument) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: WhiteboardDocument.canvasSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        for page in document.pages {
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: mediaBox.height)
            pdf.scaleBy(x: 1, y: -1)
            draw(page, in: pdf)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return data as Data
    }

    /// A PNG of one page at `scale` × the canvas size.
    static func pngData(_ page: WhiteboardPage, scale: CGFloat = 1) -> Data? {
        let size = WhiteboardDocument.canvasSize
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        draw(page, in: context)
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// Saves the whiteboard between sessions in Application Support.
struct WhiteboardStore: Sendable {
    let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.url = base.appendingPathComponent("TeachLens", isDirectory: true).appendingPathComponent("whiteboard.json")
        }
    }

    func load() -> WhiteboardDocument {
        guard let data = try? Data(contentsOf: url),
              var document = try? JSONDecoder().decode(WhiteboardDocument.self, from: data),
              !document.pages.isEmpty else { return WhiteboardDocument() }
        document.currentIndex = min(max(0, document.currentIndex), document.pages.count - 1)
        return document
    }

    func save(_ document: WhiteboardDocument) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(document) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
