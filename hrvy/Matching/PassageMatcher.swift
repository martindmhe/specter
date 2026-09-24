import Foundation

/// Finds where in the book a sequence of spoken (normalized) words comes from.
nonisolated protocol PassageMatcher: Sendable {
    func search(_ words: [String], scope: SearchScope) -> MatchSearch
}

nonisolated extension PassageMatcher {
    /// Global search; returns only a confident, unambiguous match.
    func findBestMatch(for words: [String]) -> MatchResult? {
        search(words, scope: .global).result
    }
}

/// The MVP matcher: suffix windows → rare-word candidate retrieval → fuzzy alignment →
/// confidence + uniqueness checks.
nonisolated struct RollingWindowMatcher: PassageMatcher {
    let index: BookIndex
    let configuration: MatcherConfiguration

    init(index: BookIndex, configuration: MatcherConfiguration = .default) {
        self.index = index
        self.configuration = configuration
    }

    /// A scored location for one window.
    private struct ScoredLocation {
        let alignment: SequenceAligner.Alignment
        let windowSize: Int
        var secondBestScore: Double = 0
        var candidateCount = 0
    }

    func search(_ words: [String], scope: SearchScope) -> MatchSearch {
        let words = words.filter { !$0.isEmpty }
        let windows = windowSizes(for: words.count)
        guard !windows.isEmpty else {
            return .empty(scope, reason: "Need at least \(configuration.minimumWindowSize) words")
        }

        switch scope {
        case .global: return globalSearch(words, windows: windows)
        case .near(let position): return localSearch(words, windows: windows, near: position)
        }
    }

    /// Suffix window sizes to try, e.g. 14 spoken words → [5, 8, 12, 14].
    func windowSizes(for wordCount: Int) -> [Int] {
        guard wordCount >= configuration.minimumWindowSize else { return [] }
        var sizes = configuration.windowSizes.filter { $0 <= wordCount }
        let largest = configuration.windowSizes.max() ?? wordCount
        if wordCount < largest, !sizes.contains(wordCount) {
            sizes.append(wordCount) // use every word we have
        }
        return sizes
    }

    // MARK: - Global search

    private func globalSearch(_ words: [String], windows: [Int]) -> MatchSearch {
        var confident: [ScoredLocation] = []
        var mostPromising: ScoredLocation?
        var rejection: String?
        var totalCandidates = 0

        for size in windows {
            let window = Array(words.suffix(size))
            let candidates = candidateStarts(for: window)
            totalCandidates += candidates.count

            // Fuzzy-score only the book near each candidate.
            var scored: [SequenceAligner.Alignment] = []
            for start in candidates {
                let range = (start - configuration.alignmentSlack)..<(start + size + configuration.alignmentSlack)
                if let alignment = SequenceAligner.bestAlignment(
                    of: window, in: index.normalizedWords, range: range,
                    preferredEnd: start + size - 1, configuration: configuration
                ) {
                    scored.append(alignment)
                }
            }
            scored.sort { $0.score > $1.score }
            guard let best = scored.first else { continue }

            // The runner-up must be a genuinely different place in the book.
            let separation = max(3, size / 2)
            let second = scored.dropFirst().first { abs($0.start - best.start) > separation }
            let location = ScoredLocation(alignment: best, windowSize: size,
                                          secondBestScore: second?.score ?? 0,
                                          candidateCount: candidates.count)

            var reason: String?
            if best.score < configuration.confidenceThreshold {
                reason = String(format: "Best score %.2f below threshold %.2f",
                                best.score, configuration.confidenceThreshold)
            } else if best.score - location.secondBestScore < configuration.minimumMargin {
                reason = String(format: "Ambiguous: %.2f here vs %.2f elsewhere",
                                best.score, location.secondBestScore)
            } else {
                confident.append(location)
            }

            // Remember the most promising rejected window so the debug panel can explain it.
            if let reason, best.score > (mostPromising?.alignment.score ?? -1) {
                mostPromising = location
                rejection = reason
            }
        }

        if let chosen = pickBest(confident) {
            var search = makeSearch(.global, from: chosen, isMatch: true)
            search.candidateCount = totalCandidates
            return search
        }

        guard let mostPromising else {
            var search = MatchSearch.empty(.global, reason: "No candidate locations (words unknown or too common)")
            search.candidateCount = totalCandidates
            return search
        }
        var search = makeSearch(.global, from: mostPromising, isMatch: false)
        search.candidateCount = totalCandidates
        search.rejectionReason = rejection
        return search
    }

    /// Candidate passage starts, found by letting the rarest words in the window vote.
    ///
    /// If "irrational" is the 4th spoken word and appears at book position 1024, the
    /// passage would start at 1020. Every rare word casts idf-weighted votes like this;
    /// nearby votes are merged, and the best-supported starts become candidates.
    func candidateStarts(for window: [String]) -> [Int] {
        // Group each distinct word with its offsets in the window.
        var offsetsByWord: [String: [Int]] = [:]
        for (offset, word) in window.enumerated() {
            offsetsByWord[word, default: []].append(offset)
        }

        struct WordEvidence {
            let word: String
            let offsets: [Int]
            let frequency: Int
        }
        var evidence: [WordEvidence] = []
        for (word, offsets) in offsetsByWord {
            let frequency = index.frequency(of: word)
            if frequency > 0 && frequency <= configuration.maxPostingsPerWord {
                evidence.append(WordEvidence(word: word, offsets: offsets, frequency: frequency))
            }
        }
        evidence.sort { $0.frequency != $1.frequency ? $0.frequency < $1.frequency : $0.word < $1.word }
        let informative = evidence.prefix(configuration.rareWordsPerWindow)

        var votes: [Int: Double] = [:]
        for entry in informative {
            let weight = index.idf(of: entry.word)
            for position in index.positions(of: entry.word) {
                for offset in entry.offsets {
                    votes[position - offset, default: 0] += weight
                }
            }
        }
        guard !votes.isEmpty else { return [] }

        // Merge votes within a few words of each other (insertions/omissions shift the start).
        let mergeRadius = 3
        var clusters: [(start: Int, peak: Double, total: Double)] = []
        for (start, weight) in votes.sorted(by: { $0.key < $1.key }) {
            if let last = clusters.last, start - last.start <= mergeRadius {
                let peakStart = weight > last.peak ? start : last.start
                clusters[clusters.count - 1] = (peakStart, max(weight, last.peak), last.total + weight)
            } else {
                clusters.append((start, weight, weight))
            }
        }

        return clusters
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.start < $1.start }
            .prefix(configuration.maxCandidatesPerWindow)
            .map(\.start)
    }

    // MARK: - Local search (tracking mode)

    private func localSearch(_ words: [String], windows: [Int], near position: Int) -> MatchSearch {
        let range = (position - configuration.trackingLookBehind)..<(position + configuration.trackingLookAhead)
        var accepted: [ScoredLocation] = []
        var mostPromising: ScoredLocation?

        for size in windows {
            let window = Array(words.suffix(size))
            guard let alignment = SequenceAligner.bestAlignment(
                of: window, in: index.normalizedWords, range: range,
                preferredEnd: position, configuration: configuration
            ) else { continue }

            let location = ScoredLocation(alignment: alignment, windowSize: size)
            if alignment.score >= configuration.trackingThreshold {
                accepted.append(location)
            }
            if alignment.score > (mostPromising?.alignment.score ?? -1) {
                mostPromising = location
            }
        }

        let scanned = range.clamped(to: 0..<index.wordCount).count
        if let chosen = pickBest(accepted) {
            var search = makeSearch(.near(position: position), from: chosen, isMatch: true)
            search.candidateCount = scanned
            return search
        }
        guard let mostPromising else {
            return .empty(.near(position: position), reason: "Nothing to align")
        }
        var search = makeSearch(.near(position: position), from: mostPromising, isMatch: false)
        search.candidateCount = scanned
        search.rejectionReason = String(format: "Local score %.2f below tracking threshold %.2f",
                                        mostPromising.alignment.score, configuration.trackingThreshold)
        return search
    }

    // MARK: - Helpers

    /// Picks which window's alignment to report. Short windows often score a perfect 1.0
    /// simply because they're short, so prefer the longest window scoring within
    /// `windowPreferenceTolerance` of the best — it covers more of what was actually quoted
    /// without dragging in unrelated chatter spoken before the quote.
    private func pickBest(_ locations: [ScoredLocation]) -> ScoredLocation? {
        guard let bestScore = locations.map(\.alignment.score).max() else { return nil }
        return locations
            .filter { $0.alignment.score >= bestScore - configuration.windowPreferenceTolerance }
            .max { $0.windowSize < $1.windowSize }
    }

    private func makeSearch(_ scope: SearchScope, from location: ScoredLocation, isMatch: Bool) -> MatchSearch {
        let alignment = location.alignment
        var search = MatchSearch(scope: scope)
        search.bestStart = alignment.start
        search.bestEnd = alignment.end
        search.bestScore = alignment.score
        search.secondBestScore = location.secondBestScore
        search.windowSize = location.windowSize
        if isMatch {
            search.result = makeResult(location)
        }
        return search
    }

    private func makeResult(_ location: ScoredLocation) -> MatchResult {
        let alignment = location.alignment
        let book = index.book
        let continuationEnd = alignment.end + 1 + configuration.continuationWordCount
        return MatchResult(
            startWordIndex: alignment.start,
            endWordIndex: alignment.end,
            page: book.words[alignment.start].page,
            score: alignment.score,
            secondBestScore: location.secondBestScore,
            windowSize: location.windowSize,
            matchedText: book.displayText(alignment.start..<(alignment.end + 1)),
            continuationText: book.displayText((alignment.end + 1)..<continuationEnd)
        )
    }
}
