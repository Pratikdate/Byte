import AVFoundation

/// Fallback TTS using macOS native speech synthesis
/// Used when Kokoro server is not available
class SystemTTSFallback {

    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String, emotion: String = "neutral") {
        let utterance = AVSpeechUtterance(string: text)

        // Map emotion to speech characteristics
        utterance.rate = speechRateForEmotion(emotion)
        utterance.pitchMultiplier = pitchForEmotion(emotion)
        utterance.volume = 0.9

        // Use system voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    /// Immediately stop any in-progress speech (barge-in).
    static func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private static func speechRateForEmotion(_ emotion: String) -> Float {
        switch emotion.lowercased() {
        case "excited", "happy":
            return AVSpeechUtteranceMaximumSpeechRate * 0.6  // Much faster
        case "sleepy", "sad", "bored":
            return AVSpeechUtteranceMinimumSpeechRate * 1.3  // Slower but not too slow
        case "annoyed", "angry":
            return AVSpeechUtteranceDefaultSpeechRate * 1.3  // Faster
        default:
            return AVSpeechUtteranceDefaultSpeechRate * 1.2  // Default faster (was 1.0)
        }
    }

    private static func pitchForEmotion(_ emotion: String) -> Float {
        switch emotion.lowercased() {
        case "happy", "excited":
            return 1.2  // Higher pitch
        case "sad", "lonely":
            return 0.8  // Lower pitch
        case "annoyed", "angry":
            return 1.1  // Slightly higher
        default:
            return 1.0  // Normal
        }
    }
}
