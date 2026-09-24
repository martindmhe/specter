import Foundation

/// Turns raw text (from the PDF or the speech recognizer) into comparable words.
///
/// The same normalization is applied to both sides so that "Don’t," in the book and
/// "don't" from the recognizer both become "dont".
nonisolated enum TextNormalizer {
    struct Token: Equatable {
        let original: String
        let normalized: String
        let attachesToNext: Bool
    }

    /// Characters that join two words without whitespace; the text is split after them
    /// so "well-known" is searchable as "well" + "known" (how a recognizer would say it).
    private static let joiners: Set<Character> = ["-", "‐", "‑", "‒", "–", "—", "―", "/", "…"]

    /// Apostrophe-like characters, removed entirely so contractions compare equal.
    private static let apostrophes: Set<Character> = ["'", "’", "‘", "ʼ", "′", "`", "´"]

    /// Normalizes a single word: case/diacritic folding, apostrophes removed,
    /// everything that is not a letter or digit stripped.
    static func normalize(_ word: String) -> String {
        let folded = word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        result.reserveCapacity(folded.count)
        for character in folded where !apostrophes.contains(character) {
            if character.isLetter || character.isNumber {
                result.append(character)
            }
        }
        return result
    }

    /// Normalized words of arbitrary text (used for transcripts).
    static func normalizedWords(_ text: String) -> [String] {
        tokenize(text).map(\.normalized)
    }

    /// Splits text into display tokens, each with its normalized form.
    /// Punctuation-only fragments (a lone "—" or "*") are glued onto the previous token
    /// so they still appear in the UI without becoming searchable words.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var pendingPrefix = ""

        for rawToken in cleanUp(text).split(whereSeparator: \.isWhitespace) {
            let pieces = splitOnJoiners(String(rawToken))
            for (pieceIndex, piece) in pieces.enumerated() {
                let isLastPiece = pieceIndex == pieces.count - 1
                let normalized = normalize(piece)

                if normalized.isEmpty {
                    if let last = tokens.popLast() {
                        let separator = last.attachesToNext ? "" : " "
                        tokens.append(Token(original: last.original + separator + piece,
                                            normalized: last.normalized,
                                            attachesToNext: !isLastPiece))
                    } else {
                        pendingPrefix += piece
                    }
                    continue
                }

                tokens.append(Token(original: pendingPrefix + piece,
                                    normalized: normalized,
                                    attachesToNext: !isLastPiece))
                pendingPrefix = ""
            }
        }
        return tokens
    }

    /// Removes PDF artifacts before tokenizing: soft hyphens and words hyphenated
    /// across a line break ("irra-\ntional" → "irrational").
    private static func cleanUp(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "\u{00AD}", with: "")
        cleaned = cleaned.replacingOccurrences(
            of: #"(\p{Ll})[-‐‑]\s*[\r\n]+\s*(\p{Ll})"#,
            with: "$1$2",
            options: .regularExpression
        )
        return cleaned
    }

    private static func splitOnJoiners(_ token: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for character in token {
            current.append(character)
            if joiners.contains(character) {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
