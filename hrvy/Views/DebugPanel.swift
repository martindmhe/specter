import SwiftUI

/// Matching diagnostics for tuning; lives in the window's inspector.
struct DebugPanel: View {
    let model: AppViewModel

    private var diagnostics: MatchDiagnostics { model.diagnostics }
    private var search: MatchSearch? { diagnostics.search }

    var body: some View {
        Form {
            Section("State") {
                LabeledContent("Search mode", value: diagnostics.state.trackedPosition == nil ? "Global" : "Tracking")
                LabeledContent("Tracked position", value: diagnostics.state.trackedPosition.map { "word \($0)" } ?? "—")
                LabeledContent("Local misses", value: "\(diagnostics.consecutiveMisses) / \(model.configuration.maxTrackingMisses)")
            }

            Section("Rolling transcript (\(diagnostics.rollingWords.count) words)") {
                Text(diagnostics.rollingWords.isEmpty ? "—" : diagnostics.rollingWords.joined(separator: " "))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }

            Section("Last search") {
                LabeledContent("Scope", value: scopeDescription)
                LabeledContent("Candidates", value: "\(search?.candidateCount ?? 0)")
                LabeledContent("Window", value: search?.windowSize.map { "\($0) words" } ?? "—")
                LabeledContent("Best score", value: format(search?.bestScore))
                LabeledContent("Second-best", value: format(search?.secondBestScore))
                LabeledContent("Outcome", value: outcome)
                LabeledContent("Time", value: String(format: "%.2f ms", diagnostics.elapsedMilliseconds))
                if let bestCandidate {
                    Text(bestCandidate)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Thresholds") {
                LabeledContent("Confidence", value: format(model.configuration.confidenceThreshold))
                LabeledContent("Margin", value: format(model.configuration.minimumMargin))
                LabeledContent("Tracking", value: format(model.configuration.trackingThreshold))
            }

            if let index = model.bookIndex {
                Section("Book") {
                    LabeledContent("Pages", value: "\(index.book.pageCount)")
                    LabeledContent("Words", value: index.wordCount.formatted())
                    LabeledContent("Unique words", value: index.uniqueWordCount.formatted())
                }
            }

            Button("Reset Matching") { model.resetMatching() }
        }
        .formStyle(.grouped)
    }

    private var scopeDescription: String {
        switch search?.scope {
        case .global: "Global"
        case .near(let position): "Near word \(position)"
        case nil: "—"
        }
    }

    private var outcome: String {
        guard let search else { return "—" }
        if search.result != nil { return "Match" }
        return search.rejectionReason ?? "No match"
    }

    private var bestCandidate: String? {
        guard let start = search?.bestStart, let end = search?.bestEnd, let book = model.book else { return nil }
        return "Best candidate (words \(start)–\(end), p. \(book.words[start].page)): “\(book.displayText(start..<(end + 1)))”"
    }

    private func format(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? "—"
    }
}
