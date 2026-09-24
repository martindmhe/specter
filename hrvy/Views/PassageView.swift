import SwiftUI

/// Shows the matched passage in book context: a little text before, the matched words
/// emphasized, and the continuation the speaker hasn't said yet.
struct PassageView: View {
    let book: Book
    let match: MatchResult
    let configuration: MatcherConfiguration
    let showsConfidence: Bool
    /// False once the speaker has drifted away and we're only showing the last match.
    let isLive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Label(pageLabel, systemImage: "book.pages")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isLive {
                        Text("Last match")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(passage)
                    .font(.system(size: 24, design: .serif))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsConfidence {
                    Text("Matched with \(match.score.formatted(.percent.precision(.fractionLength(0)))) confidence · runner-up \(match.secondBestScore.formatted(.percent.precision(.fractionLength(0)))) · \(match.windowSize)-word window · words \(match.startWordIndex)–\(match.endWordIndex)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .opacity(isLive ? 1 : 0.75)
        .animation(.easeOut(duration: 0.2), value: match)
        .animation(.easeOut(duration: 0.2), value: isLive)
    }

    private var pageLabel: String {
        let endPage = book.words[match.endWordIndex].page
        return endPage == match.page ? "Page \(match.page)" : "Pages \(match.page)–\(endPage)"
    }

    private var passage: AttributedString {
        let beforeStart = max(0, match.startWordIndex - configuration.contextWordsBefore)
        let afterEnd = min(book.words.count, match.endWordIndex + 1 + configuration.continuationWordCount)

        var before = AttributedString((beforeStart > 0 ? "…" : "") + book.displayText(beforeStart..<match.startWordIndex))
        before.foregroundColor = .secondary

        var matched = AttributedString(book.displayText(match.startWordIndex..<(match.endWordIndex + 1)))
        matched.foregroundColor = .accentColor
        matched.backgroundColor = Color.accentColor.opacity(0.14)
        matched.font = .system(size: 24, weight: .semibold, design: .serif)

        var after = AttributedString(book.displayText((match.endWordIndex + 1)..<afterEnd)
                                     + (afterEnd < book.words.count ? "…" : ""))
        after.foregroundColor = .primary

        var result = before
        if match.startWordIndex > beforeStart, book.needsSpace(after: match.startWordIndex - 1) {
            result += AttributedString(" ")
        }
        result += matched
        if afterEnd > match.endWordIndex + 1, book.needsSpace(after: match.endWordIndex) {
            result += AttributedString(" ")
        }
        result += after
        return result
    }
}

#Preview {
    let book = Book(text: "Economists like to say that the market can remain irrational longer than you can remain solvent. This means that being right is not enough; timing matters too.")
    let index = BookIndex(book: book)
    let match = RollingWindowMatcher(index: index).findBestMatch(
        for: TextNormalizer.normalizedWords("remain irrational longer than you can remain"))!
    return PassageView(book: book, match: match, configuration: .default, showsConfidence: true, isLive: true)
        .frame(width: 700, height: 400)
}
