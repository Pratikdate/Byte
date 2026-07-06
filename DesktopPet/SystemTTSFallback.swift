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
            return AVSpeechUtteranceDefaultSpeechRate * 1.1  // Slightly faster
        case "sleepy", "sad", "bored":
            return AVSpeechUtteranceDefaultSpeechRate * 0.9  // Slightly slower
        case "annoyed", "angry":
            return AVSpeechUtteranceDefaultSpeechRate * 1.05 // A bit faster
        default:
            return AVSpeechUtteranceDefaultSpeechRate        // Normal speed
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
