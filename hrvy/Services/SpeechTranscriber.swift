import Foundation

/// One transcript update from a speech engine.
///
/// Engines transcribe in *segments* (Apple's recognizer restarts periodically; Whisper
/// would process chunks). Within a segment, each update carries the full, possibly revised
/// text of that segment so far. Segment IDs increase monotonically.
nonisolated struct TranscriptUpdate: Equatable, Sendable {
    let segmentID: Int
    let text: String
    let isFinal: Bool
}

/// Abstraction over a streaming speech-to-text engine. Matching and UI only see this,
/// so `AppleSpeechTranscriber` can be swapped for e.g. a `WhisperSpeechTranscriber`.
protocol SpeechTranscribing: AnyObject {
    /// Called on the main actor with partial and final results.
    var onTranscriptUpdate: ((TranscriptUpdate) -> Void)? { get set }
    /// Called on the main actor if transcription stops because of an unrecoverable error.
    var onError: ((Error) -> Void)? { get set }

    func start() async throws
    func stop()
}
