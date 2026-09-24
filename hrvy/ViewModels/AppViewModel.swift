import Foundation
import Observation

/// A user-facing error, optionally with a shortcut to the System Settings pane that fixes it.
struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let settingsURL: URL?

    init(title: String, error: Error) {
        self.title = title
        let localized = error as? LocalizedError
        self.message = [localized?.errorDescription ?? error.localizedDescription, localized?.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        self.settingsURL = (error as? PermissionError)?.settingsURL
    }
}

/// App state and orchestration: book loading, listening, and feeding transcripts to the
/// matching engine. Contains no matching logic itself.
@Observable
final class AppViewModel {
    enum Status {
        case noBook, loading, ready, listening, matchFound

        var title: String {
            switch self {
            case .noBook: "No Book"
            case .loading: "Indexing…"
            case .ready: "Ready"
            case .listening: "Listening"
            case .matchFound: "Match Found"
            }
        }
    }

    let configuration: MatcherConfiguration

    private(set) var book: Book?
    private(set) var bookIndex: BookIndex?
    private(set) var isLoadingBook = false
    private(set) var isListening = false
    private(set) var isStartingToListen = false

    /// The most recent confident match; kept on screen after the speaker moves on.
    private(set) var currentMatch: MatchResult?
    private(set) var transcriptText = ""
    private(set) var diagnostics = MatchDiagnostics()

    var alert: AppAlert?
    var isImporterPresented = false
    var isDebugPanelVisible = false

    private let transcriber: any SpeechTranscribing
    private var engine: MatchingEngine?
    private var rollingTranscript: RollingTranscript
    private var lastSubmittedWords: [String] = []
    private var submittedGeneration = 0
    private var appliedGeneration = 0

    init(transcriber: any SpeechTranscribing = AppleSpeechTranscriber(),
         configuration: MatcherConfiguration = .default) {
        self.transcriber = transcriber
        self.configuration = configuration
        self.rollingTranscript = RollingTranscript(wordLimit: configuration.rollingWordLimit)
    }

    var status: Status {
        if isLoadingBook { return .loading }
        guard book != nil else { return .noBook }
        guard isListening else { return .ready }
        return diagnostics.state.trackedPosition != nil ? .matchFound : .listening
    }

    // MARK: - Book

    func openBook(at url: URL) {
        isLoadingBook = true
        Task {
            defer { isLoadingBook = false }
            do {
                // PDF parsing and indexing are CPU-heavy; keep them off the main thread.
                let (book, index) = try await Task.detached(priority: .userInitiated) {
                    let book = try PDFBookLoader.load(from: url)
                    return (book, BookIndex(book: book))
                }.value

                self.book = book
                self.bookIndex = index
                self.engine = MatchingEngine(index: index, configuration: configuration)
                resetMatching()
            } catch {
                alert = AppAlert(title: "Couldn’t Open Book", error: error)
            }
        }
    }

    // MARK: - Listening

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            Task { await startListening() }
        }
    }

    func startListening() async {
        guard book != nil, !isListening, !isStartingToListen else { return }
        isStartingToListen = true
        defer { isStartingToListen = false }

        transcriber.onTranscriptUpdate = { [weak self] update in
            self?.handle(update)
        }
        transcriber.onError = { [weak self] error in
            self?.isListening = false
            self?.alert = AppAlert(title: "Listening Stopped", error: error)
        }

        resetMatching()
        do {
            try await transcriber.start()
            isListening = true
        } catch {
            alert = AppAlert(title: "Can’t Start Listening", error: error)
        }
    }

    func stopListening() {
        transcriber.stop()
        isListening = false
    }

    /// Forget the tracked position and transcript, e.g. when switching books.
    func resetMatching() {
        rollingTranscript.clear()
        transcriptText = ""
        lastSubmittedWords = []
        currentMatch = nil
        diagnostics = MatchDiagnostics()
        if let engine {
            Task { await engine.reset() }
        }
    }

    // MARK: - Transcript → matcher

    private func handle(_ update: TranscriptUpdate) {
        rollingTranscript.apply(update)
        transcriptText = rollingTranscript.displayText

        let words = rollingTranscript.normalizedWords
        guard let engine, words != lastSubmittedWords else { return }
        lastSubmittedWords = words

        submittedGeneration += 1
        let generation = submittedGeneration
        Task {
            let diagnostics = await engine.process(words)
            // Ignore stale results (out-of-order completion or a book switched meanwhile).
            guard generation > appliedGeneration, engine === self.engine else { return }
            appliedGeneration = generation
            self.diagnostics = diagnostics
            if let result = diagnostics.search?.result {
                currentMatch = result
            }
        }
    }
}
