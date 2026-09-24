import Foundation
import Testing
@testable import hrvy

private func words(_ text: String) -> [String] {
    TextNormalizer.normalizedWords(text)
}

private func makeMatcher(_ text: String) -> RollingWindowMatcher {
    RollingWindowMatcher(index: BookIndex(book: Book(text: text)))
}

/// Global index of the `occurrence`-th (0-based) appearance of `phrase` in `book`.
private func position(of phrase: String, in book: Book, occurrence: Int = 0) -> Int {
    let target = words(phrase)
    let normalized = book.words.map(\.normalized)
    var found = 0
    for start in 0...(normalized.count - target.count) where Array(normalized[start..<(start + target.count)]) == target {
        if found == occurrence { return start }
        found += 1
    }
    Issue.record("Phrase not found: \(phrase)")
    return -1
}

private let marketBook = """
Economists like to repeat an old warning to young traders. The market can remain irrational \
longer than you can remain solvent. This means that being right about value is not enough; \
timing matters too. Many investors learn this lesson the hard way. They buy early, watch prices \
fall, and sell at the bottom just before the recovery begins.
"""

private let ballroomBook = """
At breakfast he looked at her and said nothing at all. The rain kept falling on the old tin roof \
while the kettle hissed. He looked at her again, then turned toward the window and the grey \
street beyond it. Much later that evening he looked at her across the crowded ballroom and \
finally understood what she had been trying to tell him.
"""

@Suite("Passage matching")
struct PassageMatcherTests {
    @Test func exactMatch() throws {
        let matcher = makeMatcher("the quick brown fox jumps over the lazy dog")
        let result = try #require(matcher.findBestMatch(for: words("brown fox jumps over the lazy")))
        #expect(result.startWordIndex == 2)
        #expect(result.endWordIndex == 7)
        #expect(result.score == 1.0)
        #expect(result.matchedText == "brown fox jumps over the lazy")
        #expect(result.continuationText == "dog")
        #expect(result.page == 1)
    }

    @Test func startsMidSentence() throws {
        let book = Book(text: marketBook)
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))
        let result = try #require(matcher.findBestMatch(for: words("remain irrational longer than you can remain")))

        let expectedStart = position(of: "remain irrational longer", in: book)
        #expect(result.startWordIndex == expectedStart)
        #expect(result.endWordIndex == expectedStart + 6)
        #expect(result.continuationText.hasPrefix("solvent. This means that"))
    }

    @Test func toleratesOneIncorrectWord() throws {
        let matcher = makeMatcher("the market can remain irrational longer than you can remain solvent")
        let result = try #require(matcher.findBestMatch(for: words("the market can stay irrational longer than you can remain solvent")))
        #expect(result.startWordIndex == 0)
        #expect(result.endWordIndex == 10)
        #expect(result.score >= 0.82)
        #expect(result.score < 1.0)
    }

    @Test func toleratesIncorrectWordInsideLargerBook() throws {
        let book = Book(text: marketBook)
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))
        let result = try #require(matcher.findBestMatch(for: words("the market can stay irrational longer than you can remain solvent")))
        #expect(result.endWordIndex == position(of: "solvent", in: book))
    }

    @Test func toleratesMissingWord() throws {
        let book = Book(text: marketBook)
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))
        // "longer" omitted by the recognizer.
        let result = try #require(matcher.findBestMatch(for: words("the market can remain irrational than you can remain solvent")))
        #expect(result.startWordIndex == position(of: "the market can", in: book))
        #expect(result.endWordIndex == position(of: "solvent", in: book))
    }

    @Test func toleratesPunctuationAndContractions() throws {
        let matcher = makeMatcher("“Don’t go,” she said. “It’s far too late—the trains have stopped running for the night.”")
        let result = try #require(matcher.findBestMatch(for: words("dont go she said its far too late the trains")))
        #expect(result.startWordIndex == 0)
        #expect(result.matchedText.hasPrefix("“Don’t go,”"))
    }

    @Test func shortAmbiguousPhraseIsRejected() {
        let matcher = makeMatcher(ballroomBook)
        let search = matcher.search(words("he looked at her"), scope: .global)
        #expect(search.result == nil)
        #expect(search.bestScore == 1.0)
        #expect(search.secondBestScore == 1.0)
        #expect(search.rejectionReason?.contains("Ambiguous") == true)
    }

    @Test func longerUniqueContinuationMatches() throws {
        let book = Book(text: ballroomBook)
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))
        let result = try #require(matcher.findBestMatch(for: words("he looked at her across the crowded ballroom")))
        #expect(result.startWordIndex == position(of: "he looked at her", in: book, occurrence: 2))
        #expect(result.endWordIndex == position(of: "ballroom", in: book))
        #expect(result.score - result.secondBestScore >= 0.10)
    }

    @Test func unrelatedSpeechReturnsNil() {
        let matcher = makeMatcher(marketBook)
        #expect(matcher.findBestMatch(for: words("could you please pass the salt and pepper to me")) == nil)
        #expect(matcher.findBestMatch(for: words("quantum chromodynamics describes gluons binding quarks")) == nil)
    }

    @Test func tooFewWordsReturnsNil() {
        let matcher = makeMatcher(marketBook)
        #expect(matcher.findBestMatch(for: words("irrational longer")) == nil)
    }

    @Test func ignoresLeadingChatterBeforeQuote() throws {
        let book = Book(text: marketBook)
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))
        let spoken = words("okay so my favorite line is the one that goes being right about value is not enough")
        let result = try #require(matcher.findBestMatch(for: spoken))
        #expect(result.endWordIndex == position(of: "enough", in: book))
    }

    @Test func mapsWordsToPages() throws {
        let book = Book(title: "Two pages", pageTexts: [
            "The first page talks about apples and pears in some detail.",
            "The second page describes the migration of arctic terns across oceans.",
        ])
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))
        let result = try #require(matcher.findBestMatch(for: words("migration of arctic terns across")))
        #expect(result.page == 2)
    }
}

@Suite("Tracking mode")
struct TrackingTests {
    @Test func followsReaderWordByWord() {
        let book = Book(text: marketBook)
        var tracker = QuoteTracker(matcher: RollingWindowMatcher(index: BookIndex(book: book)))
        let spoken = words("The market can remain irrational longer than you can remain solvent. This means that being right about value is not enough; timing matters too.")
        let firstSpoken = position(of: "the market can", in: book)

        var firstMatchAt: Int?
        for count in 1...spoken.count {
            let window = Array(spoken.prefix(count).suffix(30))
            let search = tracker.process(window)
            guard let result = search.result else {
                #expect(firstMatchAt == nil, "Lost the reader after \(count) words")
                continue
            }
            if firstMatchAt == nil { firstMatchAt = count }
            #expect(result.endWordIndex == firstSpoken + count - 1)
            #expect(tracker.state == .tracking(position: firstSpoken + count - 1))
        }
        // Should lock on within the first handful of words.
        #expect((firstMatchAt ?? .max) <= 6)
    }

    @Test func resolvesGloballyAmbiguousPhraseNearTrackedPosition() throws {
        let book = Book(text: ballroomBook)
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))
        var tracker = QuoteTracker(matcher: matcher)

        _ = tracker.process(words("the rain kept falling on the old tin roof"))
        let roof = position(of: "tin roof", in: book) + 1
        #expect(tracker.state == .tracking(position: roof))

        // Globally ambiguous (three occurrences)…
        #expect(matcher.findBestMatch(for: words("he looked at her")) == nil)
        // …but while tracking, the next occurrence after the tracked position wins.
        let result = try #require(tracker.process(words("he looked at her")).result)
        #expect(result.startWordIndex == position(of: "he looked at her", in: book, occurrence: 1))
    }

    @Test func toleratesRecognitionErrorsWhileTracking() throws {
        let book = Book(text: marketBook)
        var tracker = QuoteTracker(matcher: RollingWindowMatcher(index: BookIndex(book: book)))
        _ = try #require(tracker.process(words("the market can remain irrational longer than")).result)

        // Two errors in eight words (0.75) would fail the global threshold but pass tracking.
        let result = try #require(tracker.process(words("you can remain sullen this means bat being")).result)
        #expect(result.endWordIndex == position(of: "that being right", in: book) + 1)
    }

    @Test func jumpsToDistantPassage() throws {
        let filler = (0..<600).map { "filler\($0)" }.joined(separator: " ")
        let book = Book(text: marketBook + " " + filler + " " + ballroomBook)
        var tracker = QuoteTracker(matcher: RollingWindowMatcher(index: BookIndex(book: book)))

        _ = try #require(tracker.process(words("the market can remain irrational longer than you")).result)
        let result = try #require(tracker.process(words("he looked at her across the crowded ballroom and finally understood")).result)
        #expect(result.endWordIndex == position(of: "finally understood", in: book) + 1)
        #expect(tracker.state == .tracking(position: result.endWordIndex))
    }

    @Test func fallsBackToSearchingAfterRepeatedMisses() throws {
        let book = Book(text: marketBook)
        let configuration = MatcherConfiguration.default
        var tracker = QuoteTracker(matcher: RollingWindowMatcher(index: BookIndex(book: book)), configuration: configuration)
        _ = try #require(tracker.process(words("the market can remain irrational longer than you")).result)

        for _ in 0..<(configuration.maxTrackingMisses - 1) {
            #expect(tracker.process(words("what should we order for dinner tonight")).result == nil)
            #expect(tracker.state.trackedPosition != nil)
        }
        #expect(tracker.process(words("what should we order for dinner tonight")).result == nil)
        #expect(tracker.state == .searching)
    }
}

@Suite("Scale")
struct ScaleTests {
    @Test func findsQuoteInLargeBookQuickly() throws {
        // ~120k words of Zipf-ish vocabulary, then a known quote in the middle.
        var generator = SystemRandomNumberGenerator()
        let vocabulary = (0..<8_000).map { "w\($0)" }
        func randomWord() -> String {
            let rank = Int(pow(Double.random(in: 0..<1, using: &generator), 3) * Double(vocabulary.count))
            return vocabulary[rank]
        }
        let before = (0..<60_000).map { _ in randomWord() }.joined(separator: " ")
        let after = (0..<60_000).map { _ in randomWord() }.joined(separator: " ")
        let book = Book(text: before + " " + marketBook + " " + after)
        let matcher = RollingWindowMatcher(index: BookIndex(book: book))

        let spoken = words("so the market can remain irrational longer than you can remain solvent")
        let clock = ContinuousClock()
        var result: MatchResult?
        let elapsed = clock.measure {
            for _ in 0..<10 { result = matcher.findBestMatch(for: spoken) }
        }
        let match = try #require(result)
        #expect(match.endWordIndex == position(of: "remain solvent", in: book) + 1)
        #expect(elapsed / 10 < .milliseconds(50), "Matching took \(elapsed / 10) per update")
    }
}
