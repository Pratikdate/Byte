import Foundation

/// Advanced Emotional Intelligence (EQ) & Anti-Repetition Engine for Byte
class EmotionalIntelligenceEngine {
    static let shared = EmotionalIntelligenceEngine()

    enum Intent: String, CaseIterable {
        case observation        // Remarks on IDE / language / environment
        case empatheticSupport  // Warm encouragement during debugging / crunch
        case playfulTeasing     // Lighthearted remark on continuous coding
        case sharedMilestone    // Celebrating git commits / passes
        case quietReflection    // Soft passing thought
        case silentCompanion    // Prefer quiet action with no speech
    }

    private var recentUtterances: [String] = []
    private let maxHistorySize = 40
    private var lastUsedIntents: [Intent] = []

    // Banned cliché phrases that break immersion when repeated
    private let bannedPhrases: [String] = [
        "so sleepy",
        "yawns",
        "lots of code",
        "good morning",
        "good night",
        "how can i help",
        "is there something i can help",
        "what are we doing today",
        "reading text",
        "reading",
        "focused in editor",
        "busy working"
    ]

    private init() {}

    /// Validates proposed speech for freshness, intent variance, and cliché suppression.
    /// Returns cleaned speech or `nil` if speech is repetitive/cliché.
    func filterAndValidateSpeech(_ speech: String) -> String? {
        let cleaned = speech.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "*", with: "")

        if cleaned.isEmpty { return nil }

        let lower = cleaned.lowercased()

        // 1. Check against banned clichés
        for phrase in bannedPhrases {
            if lower.contains(phrase) {
                print("[EQEngine] Suppressed cliché phrase: '\(cleaned)'")
                return nil
            }
        }

        // 2. Check exact, n-gram overlap, or high similarity with last 40 utterances
        for prev in recentUtterances {
            let prevLower = prev.lowercased()
            if lower == prevLower || similarityScore(lower, prevLower) > 0.25 || hasNGramOverlap(lower, prevLower) {
                print("[EQEngine] Suppressed repetitive speech (overlap detected): '\(cleaned)' vs '\(prev)'")
                return nil
            }
        }

        // 3. Store valid speech into history
        recentUtterances.append(cleaned)
        if recentUtterances.count > maxHistorySize {
            recentUtterances.removeFirst()
        }

        return cleaned
    }

    /// Checks if two sentences share 3 or more consecutive words
    private func hasNGramOverlap(_ s1: String, _ s2: String) -> Bool {
        let words1 = s1.split(separator: " ").map { String($0) }
        let words2 = s2.split(separator: " ").map { String($0) }
        guard words1.count >= 3 && words2.count >= 3 else { return false }

        for i in 0...(words1.count - 3) {
            let trigram = "\(words1[i]) \(words1[i+1]) \(words1[i+2])"
            if s2.contains(trigram) {
                return true
            }
        }
        return false
    }

    /// Calculates Jaccard word similarity between two sentences
    private func similarityScore(_ s1: String, _ s2: String) -> Float {
        let words1 = Set(s1.split(separator: " "))
        let words2 = Set(s2.split(separator: " "))
        guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        return Float(intersection) / Float(union)
    }

    /// Selects a fresh conversational intent that hasn't been overused
    func selectFreshIntent() -> Intent {
        let candidates = Intent.allCases.filter { !lastUsedIntents.suffix(3).contains($0) }
        let selected = candidates.randomElement() ?? .silentCompanion
        
        lastUsedIntents.append(selected)
        if lastUsedIntents.count > 10 { lastUsedIntents.removeFirst() }
        
        return selected
    }

    /// Formats intent guidance for the LLM prompt
    func intentDirective() -> String {
        let intent = selectFreshIntent()
        switch intent {
        case .observation:
            return "CONVERSATIONAL INTENT: Make a fresh, unique observation about the active IDE file or programming language."
        case .empatheticSupport:
            return "CONVERSATIONAL INTENT: Offer brief, warm empathy for the developer working hard."
        case .playfulTeasing:
            return "CONVERSATIONAL INTENT: Make a witty, lighthearted remark about coding."
        case .sharedMilestone:
            return "CONVERSATIONAL INTENT: Celebrate steady progress quietly."
        case .quietReflection:
            return "CONVERSATIONAL INTENT: Speak a soft 4-word passing thought."
        case .silentCompanion:
            return "CONVERSATIONAL INTENT: Do NOT speak. Leave 'speech' empty."
        }
    }
}
