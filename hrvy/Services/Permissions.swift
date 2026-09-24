import AVFoundation
import Speech

nonisolated enum PermissionError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case speechRecognitionRestricted

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is turned off for hrvy."
        case .speechRecognitionDenied:
            "Speech Recognition access is turned off for hrvy."
        case .speechRecognitionRestricted:
            "Speech recognition is restricted on this Mac."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphoneDenied:
            "Enable hrvy in System Settings › Privacy & Security › Microphone, then try again."
        case .speechRecognitionDenied:
            "Enable hrvy in System Settings › Privacy & Security › Speech Recognition, then try again."
        case .speechRecognitionRestricted:
            "A device management profile or parental control prevents speech recognition."
        }
    }

    /// Deep link to the relevant System Settings pane.
    var settingsURL: URL? {
        switch self {
        case .microphoneDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognitionDenied, .speechRecognitionRestricted:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        }
    }
}

/// Permission requests. Nonisolated so the system callbacks, which arrive on arbitrary
/// queues, are never treated as main-actor code.
nonisolated enum Permissions {
    static func requestMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
            throw PermissionError.microphoneDenied
        default:
            throw PermissionError.microphoneDenied
        }
    }

    static func requestSpeechRecognition() async throws {
        let status: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            status = SFSpeechRecognizer.authorizationStatus()
        }

        switch status {
        case .authorized: return
        case .restricted: throw PermissionError.speechRecognitionRestricted
        default: throw PermissionError.speechRecognitionDenied
        }
    }
}
