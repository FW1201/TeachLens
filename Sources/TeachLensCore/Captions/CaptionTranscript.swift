import Foundation

/// One spoken sentence with times in seconds from the start of the caption
/// session.
struct CaptionSegment: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// Formats transcripts as SubRip (.srt), WebVTT (.vtt) or plain text.
enum CaptionFormatter {
    /// Segments shifted so `origin` becomes 0, keeping only what falls inside
    /// `range` (both in session seconds). Used to align captions with a
    /// recording that started part-way through the session.
    static func slice(_ segments: [CaptionSegment], from origin: TimeInterval, to end: TimeInterval? = nil) -> [CaptionSegment] {
        segments.compactMap { segment in
            if segment.end <= origin { return nil }
            if let end, segment.start >= end { return nil }
            var shifted = segment
            shifted.start = max(0, segment.start - origin)
            shifted.end = max(shifted.start + 0.2, segment.end - origin)
            if let end { shifted.end = min(shifted.end, end - origin) }
            return shifted
        }
    }

    static func timestamp(_ seconds: TimeInterval, separator: Character) -> String {
        let totalMs = Int((max(0, seconds) * 1000).rounded())
        let ms = totalMs % 1000
        let s = (totalMs / 1000) % 60
        let m = (totalMs / 60_000) % 60
        let h = totalMs / 3_600_000
        return String(format: "%02d:%02d:%02d", h, m, s) + String(separator) + String(format: "%03d", ms)
    }

    static func srt(_ segments: [CaptionSegment]) -> String {
        segments.enumerated().map { index, segment in
            "\(index + 1)\n\(timestamp(segment.start, separator: ",")) --> \(timestamp(segment.end, separator: ","))\n\(segment.text)\n"
        }.joined(separator: "\n")
    }

    static func vtt(_ segments: [CaptionSegment]) -> String {
        "WEBVTT\n\n" + segments.map { segment in
            "\(timestamp(segment.start, separator: ".")) --> \(timestamp(segment.end, separator: "."))\n\(segment.text)\n"
        }.joined(separator: "\n")
    }

    static func plainText(_ segments: [CaptionSegment]) -> String {
        segments.map { "[\(timestamp($0.start, separator: ".").prefix(8))] \($0.text)" }.joined(separator: "\n") + "\n"
    }
}

/// Decides when a run of partial results has become a finished sentence.
struct CaptionSentenceTracker: Sendable {
    /// Silence (no change in the partial text) that ends a sentence.
    var pause: TimeInterval = 1.2
    /// Speech recognition requests are limited to about a minute; rotate
    /// before that.
    var maximumLength: TimeInterval = 50

    private(set) var text = ""
    private(set) var startedAt: TimeInterval?
    private(set) var lastChangeAt: TimeInterval = 0

    mutating func partial(_ newText: String, at time: TimeInterval) {
        guard newText != text else { return }
        if startedAt == nil, !newText.isEmpty { startedAt = time }
        text = newText
        lastChangeAt = time
    }

    /// Returns a finished segment when the speaker paused or the request is
    /// about to hit its time limit; the tracker then starts over.
    mutating func finishIfDue(at time: TimeInterval, force: Bool = false) -> CaptionSegment? {
        guard let start = startedAt else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let paused = time - lastChangeAt >= pause
        let tooLong = time - start >= maximumLength
        guard force || paused || tooLong else { return nil }
        let end = max(lastChangeAt, start + 0.5)
        reset()
        return trimmed.isEmpty ? nil : CaptionSegment(start: start, end: end, text: trimmed)
    }

    mutating func reset() {
        text = ""
        startedAt = nil
    }
}
