import Foundation

/// Stateful layer over a `PassageMatcher` that implements searching vs. tracking mode.
///
/// - `.searching`: every update runs a global search, which must be confident *and* unique.
/// - `.tracking(position)`: after a confident match, updates first look only near the
///   last matched word with a relaxed threshold, so a reader moving forward is followed
///   smoothly even through phrases that are ambiguous book-wide. A confident global match
///   elsewhere still wins (the speaker jumped). After `maxTrackingMisses` updates without
///   a local match, the tracker falls back to `.searching`.
nonisolated struct QuoteTracker: Sendable {
    let matcher: any PassageMatcher
    let configuration: MatcherConfiguration

    private(set) var state: MatchingState = .searching
    private(set) var consecutiveMisses = 0

    init(matcher: any PassageMatcher, configuration: MatcherConfiguration = .default) {
        self.matcher = matcher
        self.configuration = configuration
    }

    mutating func reset() {
        state = .searching
        consecutiveMisses = 0
    }

    /// Processes the latest rolling window of spoken words.
    mutating func process(_ words: [String]) -> MatchSearch {
        guard case .tracking(let position) = state else {
            let global = matcher.search(words, scope: .global)
            if let result = global.result {
                state = .tracking(position: result.endWordIndex)
                consecutiveMisses = 0
            }
            return global
        }

        let local = matcher.search(words, scope: .near(position: position))
        if let result = local.result {
            state = .tracking(position: result.endWordIndex)
            consecutiveMisses = 0
            return local
        }

        // Not near the tracked position: maybe the speaker jumped somewhere else.
        let global = matcher.search(words, scope: .global)
        if let result = global.result {
            state = .tracking(position: result.endWordIndex)
            consecutiveMisses = 0
            return global
        }

        consecutiveMisses += 1
        if consecutiveMisses >= configuration.maxTrackingMisses {
            state = .searching
            consecutiveMisses = 0
        }
        return local
    }
}
