import Foundation

/// A confident location in the book for the most recent spoken words.
nonisolated struct MatchResult: Equatable, Sendable {
    /// First book word covered by the alignment.
    let startWordIndex: Int
    /// Last book word covered by the alignment (inclusive) — i.e. where the speaker is now.
    let endWordIndex: Int
    let page: Int
    /// Similarity of the spoken window to the book passage, 0...1.
    let score: Double
    /// Best score at any *other* location (0 when there was no competitor). Used for the uniqueness check.
    let secondBestScore: Double
    /// How many spoken words were used for this match.
    let windowSize: Int
    /// Original book text for `startWordIndex...endWordIndex`.
    let matchedText: String
    /// Original book text immediately following the match.
    let continuationText: String

    var wordRange: ClosedRange<Int> { startWordIndex...endWordIndex }
}

/// Which part of the book a search covers.
nonisolated enum SearchScope: Equatable, Sendable {
    /// Whole-book search via the inverted index.
    case global
    /// Search a window around a known position (tracking mode).
    case near(position: Int)
}

/// Explicit matcher mode (see `QuoteTracker`).
nonisolated enum MatchingState: Equatable, Sendable {
    case searching
    case tracking(position: Int)

    var trackedPosition: Int? {
        if case .tracking(let position) = self { return position }
        return nil
    }
}

/// The full outcome of one search, including everything needed to debug why a match
/// was or wasn't surfaced.
nonisolated struct MatchSearch: Sendable {
    var scope: SearchScope
    var result: MatchResult?
    /// Candidate locations that were fuzzy-scored (global) or book words scanned (local).
    var candidateCount = 0
    /// Best-scoring location even if it was rejected.
    var bestStart: Int?
    var bestEnd: Int?
    var bestScore: Double?
    var secondBestScore: Double?
    var windowSize: Int?
    /// Human-readable explanation when `result` is nil.
    var rejectionReason: String?

    static func empty(_ scope: SearchScope, reason: String) -> MatchSearch {
        MatchSearch(scope: scope, rejectionReason: reason)
    }
}
