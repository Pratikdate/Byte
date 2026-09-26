import Foundation

/// Enhances dialogue naturalness for TTS output
/// Adds pauses, breathing points, rhythm, and emotion-appropriate speech patterns
class DialogueNaturalness {

    /// Process raw dialogue to add natural rhythm (micro-pauses, ellipses, breathing, thinking hesitations)
    static func enhanceForSpeech(_ text: String, emotion: String) -> String {
        var enhanced = text

        // Inject organic thinking hesitation if in a thoughtful state and text doesn't already have one
        enhanced = addRelatableThinkingPrefix(enhanced, emotion: emotion)

        // Add subtle punctuation for natural pauses based on emotion
        enhanced = addEmotionalPauses(enhanced, emotion: emotion)

        // Break long sentences at natural endpoints
        enhanced = addBreathingPoints(enhanced)

        // Normalize for TTS (remove problematic characters while retaining natural pause punctuation like '...')
        enhanced = normalizeForTTS(enhanced)

        return enhanced
    }

    /// Add organic thinking hesitations for thoughtful/curious states if missing
    private static func addRelatableThinkingPrefix(_ text: String, emotion: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        
        let lower = result.lowercased()
        let hasPrefix = lower.hasPrefix("oh") || lower.hasPrefix("hmm") || lower.hasPrefix("ah") || lower.hasPrefix("well") || lower.hasPrefix("let me")
        
        if (emotion.lowercased() == "thinking" || emotion.lowercased() == "curious") && !hasPrefix {
            let fillers = [
                "Oh, okay... let me think... hmm... ",
                "Hmm, let me check... ",
                "Ah, wait... let me see... ",
                "Oh! Well... let me check... "
            ]
            if let filler = fillers.randomElement() {
                result = filler + result
            }
        }
        return result
    }

    /// Inject pauses that match emotional tone
    private static func addEmotionalPauses(_ text: String, emotion: String) -> String {
        var result = text

        switch emotion.lowercased() {
        case "sleepy", "sad", "lonely", "thinking":
            // Longer pauses, gentle trailing ellipsis
            if result.hasSuffix(".") && !result.hasSuffix("...") {
                result.removeLast()
                result += "..."
            }

        case "excited", "happy", "annoyed", "angry", "curious":
            // Clean spacing
            result = result.replacingOccurrences(of: ".", with: ". ")

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

    /// Clean text for TTS compatibility (strips metadata tags & converts ALL-CAPS words to lowercase)
    static func normalizeForTTS(_ text: String) -> String {
        var cleaned = text

        // 1. Strip bracketed metadata tags & uppercase headers
        cleaned = cleaned.replacingOccurrences(of: #"\[ACTION:[^\]]*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.replacingOccurrences(of: #"\[EMOTION:[^\]]*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.replacingOccurrences(of: #"\[CMD:[^\]]*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.replacingOccurrences(of: #"CONTEXT:"#, with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: #"RESPONSE:"#, with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: #"USER HIGHLIGHTED/SELECTED TEXT:"#, with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: #"Copied Image Analysis:"#, with: "", options: .caseInsensitive)

        // 2. Remove problematic formatting characters
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "_", with: "")
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")

        // 3. Ignore spelling out ALL-CAPS words: convert multi-letter uppercase words to lowercase for smooth TTS reading
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines)
        let filteredWords = words.compactMap { word -> String? in
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            if trimmed.isEmpty { return nil }

            if trimmed.count >= 2 && trimmed == trimmed.uppercased() && trimmed.rangeOfCharacter(from: CharacterSet.letters.inverted) == nil {
                let lower = trimmed.lowercased()
                return word.replacingOccurrences(of: trimmed, with: lower)
            }
            return word
        }
        cleaned = filteredWords.joined(separator: " ")

        // 4. Expand common abbreviations
        cleaned = cleaned.replacingOccurrences(of: "btw", with: "by the way")
        cleaned = cleaned.replacingOccurrences(of: "lol", with: "haha")
        cleaned = cleaned.replacingOccurrences(of: "omg", with: "oh my gosh")

        // 5. Remove excess whitespace
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
