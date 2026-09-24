import Foundation
import OSLog
import Speech

nonisolated enum SpeechTranscriberError: LocalizedError {
    case recognizerUnavailable
    case repeatedFailures(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "Speech recognition isn’t available for the current language right now."
        case .repeatedFailures(let message):
            "Speech recognition stopped: \(message)"
        }
    }
}

/// Streaming transcription with Apple's Speech framework.
///
/// Audio comes from an `AudioSource` (microphone by default). Recognition runs in
/// segments: a new `SFSpeechAudioBufferRecognitionRequest` is started whenever the
/// current one finishes, errors out (e.g. after silence), or has run for
/// `segmentDuration` — the recognizer is not designed for unbounded sessions. Audio keeps
/// flowing into whichever request is current, so nothing is lost across segments.
final class AppleSpeechTranscriber: SpeechTranscribing {
    var onTranscriptUpdate: ((TranscriptUpdate) -> Void)?
    var onError: ((Error) -> Void)?

    /// Proactively rotate recognition requests before they grow large or hit limits.
    static let segmentDuration: Duration = .seconds(50)
    /// A segment failing sooner than this counts toward `maxQuickFailures`.
    private static let quickFailureInterval: TimeInterval = 2
    private static let maxQuickFailures = 5

    private let audioSource: any AudioSource
    private let recognizer: SFSpeechRecognizer?
    private let requestSink = RecognitionRequestSink()
    private let logger = Logger(subsystem: "hrvy", category: "Speech")

    private var task: SFSpeechRecognitionTask?
    private var segmentID = 0
    private var segmentStartedAt = Date()
    private var quickFailures = 0
    private var isRunning = false
    private var rotationTask: Task<Void, Never>?

    init(audioSource: any AudioSource = MicrophoneAudioSource(), locale: Locale = .current) {
        self.audioSource = audioSource
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start() async throws {
        guard !isRunning else { return }
        try await Permissions.requestSpeechRecognition()
        try await Permissions.requestMicrophone()
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriberError.recognizerUnavailable
        }

        isRunning = true
        quickFailures = 0
        startSegment()

        let sink = requestSink
        do {
            try audioSource.start { buffer in sink.append(buffer) }
        } catch {
            stop()
            throw error
        }
        logger.info("Listening (on-device: \(recognizer.supportsOnDeviceRecognition))")
    }

    func stop() {
        isRunning = false
        rotationTask?.cancel()
        rotationTask = nil
        audioSource.stop()
        requestSink.replace(with: nil)?.endAudio()
        task?.cancel()
        task = nil
    }

    // MARK: - Segments

    private func startSegment() {
        guard let recognizer else { return }
        segmentID += 1
        segmentStartedAt = Date()
        let id = segmentID

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        // Prefer fully local recognition; fall back to Apple's server if unsupported.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        // Swap in the new request first so no audio is dropped, then let the old one
        // finish; its final result still arrives under its own segment ID.
        requestSink.replace(with: request)?.endAudio()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(segmentID: id, owner: self))

        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.segmentDuration)
            guard let self, !Task.isCancelled, self.isRunning, self.segmentID == id else { return }
            self.startSegment()
        }
    }

    /// Built in a nonisolated context: the Speech framework may call this on any queue.
    nonisolated private static func resultHandler(
        segmentID: Int,
        owner: AppleSpeechTranscriber
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription
            Task { @MainActor [owner] in
                owner?.handleResult(segmentID: segmentID, text: text, isFinal: isFinal, errorMessage: errorMessage)
            }
        }
    }

    private func handleResult(segmentID: Int, text: String?, isFinal: Bool, errorMessage: String?) {
        if let text, !text.isEmpty {
            quickFailures = 0
            onTranscriptUpdate?(TranscriptUpdate(segmentID: segmentID, text: text, isFinal: isFinal))
        }

        // Only the current segment ending should trigger a restart.
        guard isRunning, segmentID == self.segmentID, isFinal || errorMessage != nil else { return }

        if let errorMessage {
            logger.debug("Segment \(segmentID) ended with error: \(errorMessage, privacy: .public)")
            if Date().timeIntervalSince(segmentStartedAt) < Self.quickFailureInterval {
                quickFailures += 1
            }
            if quickFailures >= Self.maxQuickFailures {
                stop()
                onError?(SpeechTranscriberError.repeatedFailures(errorMessage))
                return
            }
        }
        startSegment()
    }
}

/// Holds the recognition request that audio buffers are appended to. The audio tap runs
/// on a real-time thread while segments are swapped on the main actor, hence the lock.
nonisolated private final class RecognitionRequestSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }

    /// Installs `newRequest` and returns the previous one.
    func replace(with newRequest: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.withLock {
            let previous = request
            request = newRequest
            return previous
        }
    }
}
