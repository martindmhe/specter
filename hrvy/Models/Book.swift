import Foundation

/// A loaded book: an ordered list of words, each mapped back to its page.
nonisolated struct Book: Sendable {
    let title: String
    let pageCount: Int
    let words: [BookWord]

    /// Builds a book from the plain text of each page (index 0 is page 1).
    /// Used by both the PDF loader and the unit tests.
    init(title: String, pageTexts: [String]) {
        self.title = title
        self.pageCount = pageTexts.count

        var words: [BookWord] = []
        for (pageIndex, pageText) in pageTexts.enumerated() {
            for token in TextNormalizer.tokenize(pageText) {
                words.append(BookWord(
                    text: token.original,
                    normalized: token.normalized,
                    page: pageIndex + 1,
                    globalIndex: words.count,
                    attachesToNext: token.attachesToNext
                ))
            }
        }
        self.words = words
    }

    /// Convenience for tests: a single-page book.
    init(title: String = "Sample", text: String) {
        self.init(title: title, pageTexts: [text])
    }

    /// Reconstructs readable original text for a range of word indices.
    func displayText(_ range: Range<Int>) -> String {
        let clamped = range.clamped(to: words.startIndex..<words.endIndex)
        var result = ""
        for index in clamped {
            let word = words[index]
            result += word.text
            if index < clamped.upperBound - 1 && !word.attachesToNext {
                result += " "
            }
        }
        return result
    }

    /// Whether a space should be rendered between word `index` and the next one.
    func needsSpace(after index: Int) -> Bool {
        guard words.indices.contains(index) else { return false }
        return !words[index].attachesToNext
    }
}
