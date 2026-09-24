import AVFoundation

/// Something that produces PCM audio buffers for a transcriber.
///
/// Transcribers depend on this rather than on the microphone directly, so a different
/// input can be plugged in without touching speech recognition or matching.
///
/// TODO: System audio — add a `SystemAudioSource` backed by ScreenCaptureKit
/// (`SCStream` with `SCStreamConfiguration.capturesAudio = true`). Its
/// `SCStreamOutput.stream(_:didOutputSampleBuffer:of: .audio)` callback would convert each
/// `CMSampleBuffer` into an `AVAudioPCMBuffer` and hand it to `onBuffer`. Then pass it to
/// `AppleSpeechTranscriber(audioSource:)`. Requires the Screen Recording permission.
nonisolated protocol AudioSource: AnyObject, Sendable {
    /// Starts producing audio. `onBuffer` is called on a real-time audio thread and must
    /// return quickly.
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

nonisolated enum AudioSourceError: LocalizedError {
    case noInputDevice

    var errorDescription: String? {
        "No microphone input is available. Check System Settings › Sound › Input."
    }
}

/// Microphone input via AVAudioEngine.
nonisolated final class MicrophoneAudioSource: AudioSource, @unchecked Sendable {
    // Only touched from start()/stop(), which the transcriber calls from the main actor.
    private let engine = AVAudioEngine()

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioSourceError.noInputDevice
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
