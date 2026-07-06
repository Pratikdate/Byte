import Foundation

/// Enhances dialogue naturalness for TTS output
/// Adds pauses, breathing points, rhythm, and emotion-appropriate speech patterns
class DialogueNaturalness {

    /// Process raw dialogue to add natural rhythm (micro-pauses, ellipses, breathing)
    static func enhanceForSpeech(_ text: String, emotion: String) -> String {
        var enhanced = text

        // Add subtle punctuation for natural pauses based on emotion
        enhanced = addEmotionalPauses(enhanced, emotion: emotion)

        // Break long sentences at natural endpoints
        enhanced = addBreathingPoints(enhanced)

        // Normalize for TTS (remove problematic characters)
        enhanced = normalizeForTTS(enhanced)

        return enhanced
    }

    /// Inject pauses that match emotional tone
    private static func addEmotionalPauses(_ text: String, emotion: String) -> String {
        var result = text

        switch emotion.lowercased() {
        case "sleepy", "sad", "lonely":
            // Longer pauses, more ellipses
            result = result.replacingOccurrences(of: ".", with: "... ")
            result = result.replacingOccurrences(of: "?", with: "...? ")

        case "excited", "happy":
            // Shorter, punchy pauses
            result = result.replacingOccurrences(of: ".", with: ". ")
            if !result.contains("!") {
                result = result.replacingOccurrences(of: ".", with: ".! ", options: [])
            }

        case "annoyed", "angry":
            // Sharp, clipped endings
            result = result.replacingOccurrences(of: ".", with: ". ")
            result = result.trimmingCharacters(in: .whitespaces)

        case "curious":
            // Questioning lilt
            result = result.replacingOccurrences(of: ".", with: ".? ")

        default:
            // Neutral: normal spacing
            result = result.replacingOccurrences(of: ".", with: ". ")
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Add line breaks at natural boundaries so Kokoro can breathe between phrases
    private static func addBreathingPoints(_ text: String) -> String {
        var result = text
        let words = text.split(separator: " ", omittingEmptySubsequences: true)

        // If sentence is long, split into smaller chunks (Kokoro handles newlines as breathing points)
        if words.count > 15 {
            var chunks: [String] = []
            var currentChunk: [String] = []

            for word in words {
                currentChunk.append(String(word))
                if currentChunk.count >= 7 || word.contains(".") || word.contains("?") {
                    chunks.append(currentChunk.joined(separator: " "))
                    currentChunk = []
                }
            }

            if !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: " "))
            }

            result = chunks.joined(separator: "\n")
        }

        return result
    }

    /// Clean text for TTS compatibility
    private static func normalizeForTTS(_ text: String) -> String {
        var cleaned = text

        // Remove problematic characters
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "_", with: "")
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")

        // Expand common abbreviations
        cleaned = cleaned.replacingOccurrences(of: "btw", with: "by the way")
        cleaned = cleaned.replacingOccurrences(of: "lol", with: "haha")
        cleaned = cleaned.replacingOccurrences(of: "omg", with: "oh my gosh")

        // Remove excess whitespace
        let components = cleaned.components(separatedBy: .whitespaces)
        cleaned = components.filter { !$0.isEmpty }.joined(separator: " ")

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Map PetEmotion to TTS emotion string for Kokoro
    static func ttsEmotionLabel(_ emotion: String) -> String {
        switch emotion.lowercased() {
        case "happy", "excited", "proud":
            return "happy"
        case "sad", "lonely":
            return "sad"
        case "angry", "annoyed":
            return "angry"
        case "curious", "shocked":
            return "surprised"
        case "sleepy", "bored":
            return "calm"
        case "love":
            return "tender"
        default:
            return "neutral"
        }
    }

    /// Generate dialogue with context-aware variation to avoid repetition
    static func ensureVariation(_ candidate: String, previousLines: [String]) -> Bool {
        // Don't repeat last 3 lines exactly
        for prev in previousLines.suffix(3) {
            if candidate.lowercased().trimmingCharacters(in: .punctuationCharacters)
                == prev.lowercased().trimmingCharacters(in: .punctuationCharacters) {
                return false
            }
        }

        // Check for phrase overlap (reject if more than 60% of words match)
        let candidateWords = Set(candidate.lowercased().split(separator: " "))
        for prev in previousLines.suffix(5) {
            let prevWords = Set(prev.lowercased().split(separator: " "))
            let overlap = candidateWords.intersection(prevWords).count
            let maxWords = max(candidateWords.count, prevWords.count)

            if maxWords > 0 && Float(overlap) / Float(maxWords) > 0.6 {
                return false
            }
        }

        return true
    }

    /// Build context prompt that preserves conversational memory
    static func buildDialogueContext(userMessage: String?, previousExchanges: [String]) -> String {
        var context = ""

        if !previousExchanges.isEmpty {
            context += "Recent conversation:\n"
            for exchange in previousExchanges.suffix(4) {
                context += "- \(exchange)\n"
            }
            context += "\n"
        }

        if let msg = userMessage, !msg.isEmpty {
            context += "User just said: \"\(msg)\"\n"
        }

        return context
    }
}
