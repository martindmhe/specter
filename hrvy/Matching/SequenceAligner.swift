import Foundation

/// Token-level fuzzy alignment of spoken words against a stretch of book words.
///
/// This is a weighted edit distance ("semi-global" alignment): every spoken word must be
/// accounted for, but the passage may start and end anywhere inside the book range.
/// The cost of the cheapest alignment is turned into a 0...1 similarity:
///
///     score = 1 - cost / spokenWordCount
///
/// So one wrong word in a 12-word window costs 1.0 → score 0.917.
nonisolated enum SequenceAligner {
    struct Alignment: Equatable {
        /// First book word used by the alignment.
        let start: Int
        /// Last book word used by the alignment (inclusive).
        let end: Int
        let cost: Double
        let score: Double
    }

    /// Finds the best alignment of `query` ending anywhere in `range`.
    ///
    /// - Parameter preferredEnd: when several end positions tie on cost, choose the one
    ///   closest to this book position (used to keep tracking mode from jumping).
    static func bestAlignment(
        of query: [String],
        in book: [String],
        range: Range<Int>,
        preferredEnd: Int? = nil,
        configuration: MatcherConfiguration
    ) -> Alignment? {
        let range = range.clamped(to: book.startIndex..<book.endIndex)
        let m = query.count
        let n = range.count
        guard m > 0, n > 0 else { return nil }

        let extra = configuration.extraSpokenWordCost
        let skip = configuration.skippedBookWordCost

        // Two rolling rows of the DP table. cost[j] = cheapest way to consume the first i
        // query words with the alignment ending just before book word (range.lowerBound + j).
        // start[j] tracks where that alignment began in the book.
        var previousCost = [Double](repeating: 0, count: n + 1)
        var previousStart = (0...n).map { range.lowerBound + $0 } // free leading book words
        var currentCost = [Double](repeating: 0, count: n + 1)
        var currentStart = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            let spoken = query[i - 1]
            currentCost[0] = Double(i) * extra
            currentStart[0] = range.lowerBound

            for j in 1...n {
                let bookWord = book[range.lowerBound + j - 1]

                var best = previousCost[j - 1] + substitutionCost(spoken, bookWord, configuration)
                var bestStart = previousStart[j - 1]

                let extraWord = previousCost[j] + extra
                if extraWord < best {
                    best = extraWord
                    bestStart = previousStart[j]
                }

                let skippedWord = currentCost[j - 1] + skip
                if skippedWord < best {
                    best = skippedWord
                    bestStart = currentStart[j - 1]
                }

                currentCost[j] = best
                currentStart[j] = bestStart
            }
            swap(&previousCost, &currentCost)
            swap(&previousStart, &currentStart)
        }

        // previous* now holds the final row: the full query consumed, ending at each column.
        var bestColumn: Int?
        for j in 1...n {
            let end = range.lowerBound + j - 1
            guard previousStart[j] <= end else { continue } // alignment consumed no book words
            guard let current = bestColumn else { bestColumn = j; continue }

            let cost = previousCost[j]
            let currentBest = previousCost[current]
            if cost < currentBest - 1e-9 {
                bestColumn = j
            } else if abs(cost - currentBest) <= 1e-9, let preferredEnd {
                let currentEnd = range.lowerBound + current - 1
                if distance(end, from: preferredEnd) < distance(currentEnd, from: preferredEnd) {
                    bestColumn = j
                }
            }
        }

        guard let column = bestColumn else { return nil }
        let cost = previousCost[column]
        return Alignment(
            start: previousStart[column],
            end: range.lowerBound + column - 1,
            cost: cost,
            score: max(0, 1 - cost / Double(m))
        )
    }

    /// Cost of aligning one spoken word with one book word.
    static func substitutionCost(_ spoken: String, _ book: String, _ configuration: MatcherConfiguration) -> Double {
        if spoken == book { return 0 }
        return isNearMiss(spoken, book) ? configuration.nearMissCost : configuration.substitutionCost
    }

    /// Words that are probably the same word misheard or inflected differently:
    /// a shared stem ("remain"/"remains", "walk"/"walked") or ≥ 75% character similarity.
    static func isNearMiss(_ a: String, _ b: String) -> Bool {
        let lengthA = a.count, lengthB = b.count
        guard min(lengthA, lengthB) >= 3, abs(lengthA - lengthB) <= 3 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        guard min(lengthA, lengthB) >= 4, abs(lengthA - lengthB) <= 2 else { return false }
        let distance = levenshtein(Array(a), Array(b))
        return 1 - Double(distance) / Double(max(lengthA, lengthB)) >= 0.75
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Distance biased forward: readers usually continue ahead rather than jump back.
    private static func distance(_ position: Int, from anchor: Int) -> Int {
        position >= anchor ? position - anchor : (anchor - position) * 2
    }
}
