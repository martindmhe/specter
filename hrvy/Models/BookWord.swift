import Foundation

/// A single searchable word extracted from the book.
///
/// `text` keeps the original characters (punctuation, capitalization, curly quotes)
/// so the UI can show the real book text; `normalized` is what the matcher compares.
nonisolated struct BookWord: Hashable, Sendable {
    /// Original text as it appears in the book, including attached punctuation.
    let text: String
    /// Lowercased, punctuation-free form used for indexing and matching.
    let normalized: String
    /// 1-based page number.
    let page: Int
    /// Position of this word in the whole book (0-based, contiguous).
    let globalIndex: Int
    /// True when the next word should be rendered without a space in between
    /// (e.g. the two halves of "well-known").
    let attachesToNext: Bool
}
