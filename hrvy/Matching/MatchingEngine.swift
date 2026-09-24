import Foundation
import OSLog

/// Everything the debug panel shows about the latest update.
nonisolated struct MatchDiagnostics: Sendable {
    var rollingWords: [String] = []
    var search: MatchSearch?
    var state: MatchingState = .searching
    var consecutiveMisses = 0
    var elapsedMilliseconds: Double = 0
}

/// Runs matching off the main thread. Owns the tracker state for one loaded book.
actor MatchingEngine {
    private var tracker: QuoteTracker
    private let logger = Logger(subsystem: "hrvy", category: "Matching")

    init(index: BookIndex, configuration: MatcherConfiguration = .default) {
        let matcher = RollingWindowMatcher(index: index, configuration: configuration)
        self.tracker = QuoteTracker(matcher: matcher, configuration: configuration)
    }

    func process(_ words: [String]) -> MatchDiagnostics {
        let clock = ContinuousClock()
        let started = clock.now
        let search = tracker.process(words)
        let elapsed = started.duration(to: clock.now)

        let diagnostics = MatchDiagnostics(
            rollingWords: words,
            search: search,
            state: tracker.state,
            consecutiveMisses: tracker.consecutiveMisses,
            elapsedMilliseconds: elapsed / .milliseconds(1)
        )
        log(diagnostics)
        return diagnostics
    }

    func reset() {
        tracker.reset()
    }

    private func log(_ diagnostics: MatchDiagnostics) {
        guard let search = diagnostics.search else { return }
        let mode = search.scope == .global ? "global" : "tracking"
        let best = search.bestScore.map { String(format: "%.2f", $0) } ?? "-"
        let second = search.secondBestScore.map { String(format: "%.2f", $0) } ?? "-"
        let outcome = search.result.map { "MATCH \($0.startWordIndex)…\($0.endWordIndex)" }
            ?? (search.rejectionReason ?? "no match")
        logger.debug("""
            [\(mode, privacy: .public)] candidates=\(search.candidateCount) best=\(best, privacy: .public) \
            second=\(second, privacy: .public) window=\(search.windowSize ?? 0) \
            \(outcome, privacy: .public) (\(diagnostics.elapsedMilliseconds, format: .fixed(precision: 2)) ms) \
            "\(diagnostics.rollingWords.joined(separator: " "), privacy: .public)"
            """)
    }
}
