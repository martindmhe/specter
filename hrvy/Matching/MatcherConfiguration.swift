import Foundation

/// Every tunable knob of the matching pipeline in one place.
nonisolated struct MatcherConfiguration: Sendable {
    // MARK: Rolling window

    /// Maximum spoken words kept in the rolling transcript.
    var rollingWordLimit = 30
    /// Suffix windows (most recent N spoken words) tried on every update.
    var windowSizes = [5, 8, 12, 16, 20]
    /// Fewer spoken words than this are never matched.
    var minimumWindowSize = 4
    /// When several windows match, report the longest one scoring within this of the best.
    var windowPreferenceTolerance = 0.10

    // MARK: Confidence (global search)

    /// A global match must score at least this…
    var confidenceThreshold = 0.82
    /// …and beat the best *other* location by at least this much.
    var minimumMargin = 0.10

    // MARK: Candidate retrieval

    /// How many of the rarest distinct words in a window vote for candidate locations.
    var rareWordsPerWindow = 6
    /// Words occurring more often than this are too common to generate candidates.
    var maxPostingsPerWord = 3_000
    /// Candidate locations fuzzy-scored per window, after voting.
    var maxCandidatesPerWindow = 24
    /// Extra book words on each side of a candidate when aligning (absorbs insertions/omissions).
    var alignmentSlack = 6

    // MARK: Fuzzy scoring costs (token-level edit distance)

    /// Spoken word differs from book word.
    var substitutionCost = 1.0
    /// Spoken word is a near miss ("remain"/"remains", "color"/"colour").
    var nearMissCost = 0.35
    /// Recognizer produced a word the book doesn't have.
    var extraSpokenWordCost = 1.0
    /// Speaker/recognizer skipped a book word.
    var skippedBookWordCost = 1.0

    // MARK: Tracking mode

    /// A local match near the tracked position only needs this score (no margin test).
    var trackingThreshold = 0.70
    var trackingLookBehind = 100
    var trackingLookAhead = 300
    /// Consecutive updates without a local match before falling back to global search.
    var maxTrackingMisses = 6

    // MARK: Display

    var contextWordsBefore = 14
    var continuationWordCount = 50

    static let `default` = MatcherConfiguration()
}
