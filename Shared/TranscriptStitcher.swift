import CoreMedia
import Foundation

/// Apple speech modules emit one result per utterance (and revisions of the same
/// range). Compare and live Cadence stitch those into a single transcript,
/// preferring finalized hypotheses over volatile partials.
enum TranscriptStitcher {
    struct Piece: Sendable {
        var start: Double
        var end: Double
        var text: String
        var isFinal: Bool
    }

    static func ingest(
        _ pieces: inout [Piece],
        range: CMTimeRange,
        text: String,
        isFinal: Bool = false
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let start: Double
        if range.start.isValid, range.start.seconds.isFinite {
            start = max(0, range.start.seconds)
        } else {
            start = pieces.last?.end ?? 0
        }
        let duration = range.duration.isValid && range.duration.seconds.isFinite
            ? range.duration.seconds
            : 0
        let end = start + max(duration, 0.05)

        if let idx = pieces.firstIndex(where: { overlaps($0, start: start, end: end) }) {
            let existing = pieces[idx]
            if shouldReplace(existing: existing, incoming: trimmed, isFinal: isFinal) {
                pieces[idx].text = trimmed
                pieces[idx].start = min(existing.start, start)
                pieces[idx].end = max(existing.end, end)
                if isFinal { pieces[idx].isFinal = true }
            }
            pieces.sort { $0.start < $1.start }
            return
        }

        if let idx = pieces.firstIndex(where: { trimmed.hasPrefix($0.text) && trimmed.count > $0.text.count }) {
            pieces[idx].text = trimmed
            pieces[idx].start = min(pieces[idx].start, start)
            pieces[idx].end = max(pieces[idx].end, end)
            if isFinal { pieces[idx].isFinal = true }
            pieces.sort { $0.start < $1.start }
            return
        }

        if pieces.contains(where: { $0.text.hasPrefix(trimmed) && $0.text.count > trimmed.count && $0.isFinal }) {
            return
        }

        pieces.removeAll { shouldReplace(existing: $0, start: start, end: end) && !$0.isFinal }
        pieces.append(Piece(start: start, end: end, text: trimmed, isFinal: isFinal))
        pieces.sort { $0.start < $1.start }
    }

    static func assembled(_ pieces: [Piece]) -> String {
        let finals = pieces.filter(\.isFinal)
        let source = finals.isEmpty ? pieces : finals
        return source.map(\.text).joined(separator: " ")
    }

    static func coverageEnd(_ pieces: [Piece]) -> Double {
        pieces.map(\.end).max() ?? 0
    }

    static func mergeText(_ existing: String, _ incoming: String) -> String {
        absorbRevision(existing: existing, incoming: incoming, allowConcatenate: true)
    }

    /// SpeechTranscriber revisions of the same take — keep the best single hypothesis, do not glue.
    static func absorbRevision(
        existing: String,
        incoming: String,
        allowConcatenate: Bool = false
    ) -> String {
        let incoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if incoming.isEmpty { return existing }
        if existing.isEmpty { return incoming }
        if incoming == existing { return existing }
        if incoming.hasPrefix(existing) { return incoming }
        if existing.hasPrefix(incoming) { return existing }
        if existing.contains(incoming) { return existing }
        if incoming.contains(existing) { return incoming }
        if revisionOverlap(existing, incoming) >= 0.55 {
            return incoming.count >= existing.count ? incoming : existing
        }
        if allowConcatenate {
            return existing + " " + incoming
        }
        return incoming.count >= existing.count ? incoming : existing
    }

  private static func revisionOverlap(_ a: String, _ b: String) -> Double {
        let wordsA = a.lowercased().split(separator: " ").map(String.init)
        let wordsB = b.lowercased().split(separator: " ").map(String.init)
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let setA = Set(wordsA)
        let intersection = wordsB.filter { setA.contains($0) }.count
        return Double(intersection) / Double(max(wordsA.count, wordsB.count))
    }

    private static func overlaps(_ piece: Piece, start: Double, end: Double) -> Bool {
        let overlap = min(piece.end, end) - max(piece.start, start)
        guard overlap > 0 else { return false }
        let union = max(piece.end, end) - min(piece.start, start)
        return union > 0 && (overlap / union) >= 0.45
    }

    private static func shouldReplace(existing: Piece, start: Double, end: Double) -> Bool {
        overlaps(existing, start: start, end: end) && !existing.isFinal
    }

    private static func shouldReplace(existing: Piece, incoming: String, isFinal: Bool) -> Bool {
        if isFinal, !existing.isFinal { return true }
        if isFinal, existing.isFinal, score(incoming) > score(existing.text) { return true }
        if !isFinal, existing.isFinal { return false }
        if incoming.count > existing.text.count { return true }
        if incoming.count == existing.text.count, score(incoming) > score(existing.text) { return true }
        return incoming.hasPrefix(existing.text) && incoming.count > existing.text.count
    }

    /// Prefer hypotheses that look written (punctuation, capitals).
    private static func score(_ text: String) -> Int {
        var points = text.count
        points += text.filter { ".!?".contains($0) }.count * 8
        points += text.filter { $0.isUppercase }.count * 2
        return points
    }
}
