import Foundation

/// Inverted index over a book's normalized words, built once when the book is loaded.
///
///     "irrational" -> [1024, 8400]
///     "market"     -> [1019, 3920, 9003]
///
/// Lookups are O(1); the posting-list length doubles as the word's document frequency,
/// which tells the matcher how informative a word is.
nonisolated final class BookIndex: Sendable {
    let book: Book
    /// Normalized words in book order (contiguous copy for fast alignment).
    let normalizedWords: [String]
    private let postings: [String: [Int]]

    init(book: Book) {
        self.book = book
        self.normalizedWords = book.words.map(\.normalized)

        var postings: [String: [Int]] = [:]
        for (position, word) in normalizedWords.enumerated() {
            postings[word, default: []].append(position)
        }
        self.postings = postings
    }

    var wordCount: Int { normalizedWords.count }
    var uniqueWordCount: Int { postings.count }

    /// Global positions of `word` in the book (sorted ascending).
    func positions(of word: String) -> [Int] {
        postings[word] ?? []
    }

    func frequency(of word: String) -> Int {
        postings[word]?.count ?? 0
    }

    /// Inverse document frequency: rare words carry more evidence than common ones.
    func idf(of word: String) -> Double {
        let frequency = Double(max(self.frequency(of: word), 1))
        return log(1 + Double(wordCount) / frequency)
    }
}
