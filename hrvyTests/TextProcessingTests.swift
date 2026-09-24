import AppKit
import Foundation
import Testing
@testable import hrvy

@Suite("Normalization")
struct TextNormalizerTests {
    @Test func normalizesCasePunctuationAndApostrophes() {
        #expect(TextNormalizer.normalize("Don’t,") == "dont")
        #expect(TextNormalizer.normalize("don't") == "dont")
        #expect(TextNormalizer.normalize("“Hello!”") == "hello")
        #expect(TextNormalizer.normalize("Café") == "cafe")
        #expect(TextNormalizer.normalize("1984.") == "1984")
    }

    @Test func splitsHyphenatedWordsButKeepsOriginalText() {
        let tokens = TextNormalizer.tokenize("A well-known   fact—really.")
        #expect(tokens.map(\.normalized) == ["a", "well", "known", "fact", "really"])
        let book = Book(text: "A well-known   fact—really.")
        #expect(book.displayText(0..<book.words.count) == "A well-known fact—really.")
    }

    @Test func joinsWordsHyphenatedAcrossLineBreaks() {
        #expect(TextNormalizer.normalizedWords("remain irra-\ntional longer") == ["remain", "irrational", "longer"])
    }

    @Test func attachesStandalonePunctuationToPreviousWord() {
        let book = Book(text: "He paused — then spoke.")
        #expect(book.words.map(\.normalized) == ["he", "paused", "then", "spoke"])
        #expect(book.displayText(0..<book.words.count) == "He paused — then spoke.")
    }
}

@Suite("Alignment")
struct SequenceAlignerTests {
    let configuration = MatcherConfiguration.default

    @Test func nearMisses() {
        #expect(SequenceAligner.isNearMiss("remain", "remains"))
        #expect(SequenceAligner.isNearMiss("colour", "color"))
        #expect(!SequenceAligner.isNearMiss("stay", "remain"))
        #expect(!SequenceAligner.isNearMiss("at", "a"))
    }

    @Test func alignmentFindsSubsequenceAndScoresErrors() throws {
        let book = "a b the market can remain irrational longer c d".split(separator: " ").map(String.init)
        let exact = try #require(SequenceAligner.bestAlignment(
            of: ["market", "can", "remain"], in: book, range: 0..<book.count, configuration: configuration))
        #expect(exact.start == 3 && exact.end == 5 && exact.score == 1)

        let oneWrong = try #require(SequenceAligner.bestAlignment(
            of: ["market", "can", "stay", "irrational"], in: book, range: 0..<book.count, configuration: configuration))
        #expect(oneWrong.start == 3 && oneWrong.end == 6)
        #expect(oneWrong.score == 0.75)
    }
}

@Suite("Rolling transcript")
struct RollingTranscriptTests {
    @Test func partialResultsReplaceSegmentText() {
        var transcript = RollingTranscript(wordLimit: 30)
        transcript.apply(TranscriptUpdate(segmentID: 1, text: "the market", isFinal: false))
        transcript.apply(TranscriptUpdate(segmentID: 1, text: "the market can remain", isFinal: false))
        #expect(transcript.normalizedWords == ["the", "market", "can", "remain"])
    }

    @Test func segmentsAreConcatenatedAndTrimmed() {
        var transcript = RollingTranscript(wordLimit: 5)
        transcript.apply(TranscriptUpdate(segmentID: 1, text: "one two three four", isFinal: true))
        transcript.apply(TranscriptUpdate(segmentID: 2, text: "Five, six", isFinal: false))
        #expect(transcript.normalizedWords == ["two", "three", "four", "five", "six"])
        // A late final result for an older segment doesn't reorder things.
        transcript.apply(TranscriptUpdate(segmentID: 1, text: "one two three four", isFinal: true))
        #expect(transcript.normalizedWords == ["two", "three", "four", "five", "six"])
    }
}

@Suite("PDF loading")
struct PDFBookLoaderTests {
    @Test func extractsWordsWithPageNumbers() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hrvy-test-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePDF(pages: [
            "The market can remain irrational longer than you can remain solvent.",
            "Timing matters too.",
        ], to: url)

        let book = try PDFBookLoader.load(from: url)
        #expect(book.pageCount == 2)
        #expect(book.words.first?.normalized == "the")
        #expect(book.words.last?.normalized == "too")
        #expect(book.words.last?.page == 2)
        #expect(book.words.enumerated().allSatisfy { $0.offset == $0.element.globalIndex })
    }

    private func writePDF(pages: [String], to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for text in pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
                .draw(in: CGRect(x: 72, y: 72, width: 468, height: 648))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
    }
}
