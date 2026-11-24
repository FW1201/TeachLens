import AppKit
import CoreGraphics
import ImageIO

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
}

struct WhiteboardColor: Codable, Equatable, Sendable {
    var r: Double, g: Double, b: Double

    var cgColor: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }

    static let palette: [WhiteboardColor] = [
        WhiteboardColor(r: 0.10, g: 0.10, b: 0.12), WhiteboardColor(r: 0.93, g: 0.20, b: 0.20),
        WhiteboardColor(r: 0.12, g: 0.45, b: 0.95), WhiteboardColor(r: 0.10, g: 0.66, b: 0.35),
        WhiteboardColor(r: 0.98, g: 0.62, b: 0.05), WhiteboardColor(r: 0.85, g: 0.69, b: 0.24),
        WhiteboardColor(r: 1, g: 1, b: 1),
    ]
}

struct WhiteboardStroke: Codable, Equatable, Sendable {
    var points: [CGPoint]
    var color: WhiteboardColor
    var width: Double
    var isHighlighter: Bool
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

    mutating func go(_ delta: Int) {
        currentIndex = min(max(0, currentIndex + delta), pages.count - 1)
    }

    /// Removes strokes that pass within `radius` of `point` on the current page.
    mutating func erase(at point: CGPoint, radius: Double) {
        currentPage.strokes.removeAll { stroke in
            Self.distance(from: point, to: stroke.points) <= radius + stroke.width / 2
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
            guard let first = stroke.points.first else { continue }
            context.setStrokeColor(stroke.color.cgColor.copy(alpha: stroke.isHighlighter ? 0.35 : 1) ?? stroke.color.cgColor)
            context.setLineWidth(stroke.width)
            context.move(to: first)
            if stroke.points.count == 1 {
                context.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            }
            for point in stroke.points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
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
struct WhiteboardStore {
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
