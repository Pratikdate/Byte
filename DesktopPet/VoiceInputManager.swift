import Foundation
import AVFoundation

/// Unified voice I/O manager using local faster-whisper (STT) + Kokoro (TTS)
/// All processing on-device: whisper for speech-to-text, Kokoro for natural TTS.
class VoiceInputManager {
    static let shared = VoiceInputManager()

    private let audioManager = AudioManager.shared

    var onTranscriptionUpdate: ((String) -> Void)?
    var onFinishedTranscribing: ((String) -> Void)?
    private(set) var currentTranscript: String = ""

    init() {
        setupAudioManagerCallbacks()
    }

    private func setupAudioManagerCallbacks() {
        audioManager.onTranscriptionUpdate = { [weak self] text in
            self?.currentTranscript = text
            if !text.isEmpty { DialogueContextTracker.shared.recordInteraction() }
            self?.onTranscriptionUpdate?(text)
        }

        audioManager.onTranscriptionFinished = { [weak self] text in
            self?.currentTranscript = text
            if !text.isEmpty { DialogueContextTracker.shared.recordInteraction() }
            self?.onFinishedTranscribing?(text)
        }
    }

    func startListening(completion: @escaping (Bool) -> Void) {
        currentTranscript = ""
        // macOS microphone permissions handled at system level
        // Just start listening
        DispatchQueue.main.async {
            self.audioManager.startListening()
            completion(true)
        }
    }

    func stopListening() {
        audioManager.stopListening()
    }

    func finishListeningWithResult(completion: @escaping (String) -> Void) {
        audioManager.stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            completion(self.currentTranscript)
        }
    }

    /// Speak dialogue with emotion-aware TTS
    /// - Parameters:
    ///   - text: what to say
    ///   - emotion: emotional tone (happy, sad, calm, excited, sleepy, etc.)
    func speak(_ text: String, emotion: String = "neutral") {
        let speed = speedForEmotion(emotion)
        audioManager.speak(text, emotion: emotion, speed: speed)
    }

    private func speedForEmotion(_ emotion: String) -> Float {
        switch emotion.lowercased() {
        case "excited", "happy": return 1.2
        case "sleepy", "sad": return 0.8
        case "annoyed": return 1.1
        default: return 1.0
        }
    }
}
