import Foundation

/// Stitches segmented transcript updates into one rolling window of recent words.
///
/// Partial results revise the whole segment each time ("the market" → "the market can
/// remain"), so each segment is replaced wholesale and only the tail of the concatenation
/// is kept.
nonisolated struct RollingTranscript: Sendable {
    let wordLimit: Int
    private var segments: [(id: Int, rawWords: [String])] = []

    init(wordLimit: Int) {
        self.wordLimit = wordLimit
    }

    mutating func apply(_ update: TranscriptUpdate) {
        let rawWords = update.text.split(whereSeparator: \.isWhitespace).map(String.init)
        if let index = segments.firstIndex(where: { $0.id == update.segmentID }) {
            segments[index].rawWords = rawWords
        } else {
            segments.append((update.segmentID, rawWords))
            segments.sort { $0.id < $1.id }
        }
        // Old segments beyond the window are no longer needed.
        while segments.count > 1, segments.dropFirst().reduce(0, { $0 + $1.rawWords.count }) >= wordLimit * 2 {
            segments.removeFirst()
        }
    }

    mutating func clear() {
        segments.removeAll()
    }

    /// The most recent spoken words, normalized for matching.
    var normalizedWords: [String] {
        Array(recentRawWords.flatMap(TextNormalizer.normalizedWords).suffix(wordLimit))
    }

    /// The most recent spoken words as the recognizer formatted them, for display.
    var displayText: String {
        recentRawWords.suffix(wordLimit).joined(separator: " ")
    }

    private var recentRawWords: [String] {
        Array(segments.flatMap(\.rawWords).suffix(wordLimit * 2))
    }
}
