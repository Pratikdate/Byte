import Foundation
import AppKit

/// Advanced Emotional Intelligence (EQ) & Anti-Repetition Engine for Byte
class EmotionalIntelligenceEngine {
    static let shared = EmotionalIntelligenceEngine()

    enum Intent: String, CaseIterable {
        case observation        // Remarks on IDE / language / environment
        case empatheticSupport  // Warm encouragement during debugging / crunch
        case playfulTeasing     // Lighthearted remark on continuous coding
        case sharedMilestone    // Celebrating git commits / passes
        case activeCuriosity    // Ask a brief, friendly question to learn user preferences
        case energyMirroring    // Mirror user focus energy state softly
        case habitReflection    // Reflect on Byte's growing bond with user
        case quietReflection    // Soft passing thought
        case silentCompanion    // Prefer quiet action with no speech
    }

    private var recentUtterances: [String] = []
    private let maxHistorySize = 40
    private var lastUsedIntents: [Intent] = []

    // Banned cliché phrases that break companion immersion when repeated
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
        "busy working",
        "as an ai",
        "i am here to help",
        "i am here to assist",
        "doing great work",
        "keep it up",
        "how can i assist"
    ]

    private init() {}

    /// Validates proposed speech for freshness, intent variance, and cliché suppression.
    /// Returns cleaned speech or `nil` if speech is repetitive/cliché.
    func filterAndValidateSpeech(_ speech: String, isUserDirected: Bool = false) -> String? {
        let cleaned = speech.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "*", with: "")

        if cleaned.isEmpty { return nil }

        let lower = cleaned.lowercased()

        // User-directed responses must ALWAYS be delivered to the user (unless 100% exact duplicate of the immediate last line)
        if isUserDirected {
            if let last = recentUtterances.last, last.lowercased() == lower {
                // Slightly vary if exact duplicate
                print("[EQEngine] User-directed reply was exact duplicate of last sentence. Allowing anyway for responsiveness.")
            }
            recentUtterances.append(cleaned)
            if recentUtterances.count > maxHistorySize {
                recentUtterances.removeFirst()
            }
            return cleaned
        }

        // 1. Check against banned clichés (ambient only)
        for phrase in bannedPhrases {
            if lower.contains(phrase) {
                print("[EQEngine] Suppressed cliché phrase: '\(cleaned)'")
                return nil
            }
        }

        // 2. Check exact or high similarity (>0.65 Jaccard overlap) with recent 10 utterances
        for prev in recentUtterances.suffix(10) {
            let prevLower = prev.lowercased()
            if lower == prevLower || similarityScore(lower, prevLower) > 0.65 {
                print("[EQEngine] Suppressed repetitive ambient speech: '\(cleaned)' vs '\(prev)'")
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
        let personality = SettingsManager.shared.activePersonality
        
        switch intent {
        case .observation:
            return "CONVERSATIONAL INTENT: Make a fresh, unique observation about the active IDE file or programming language. (Reflect your \(personality.rawValue) personality)."
        case .empatheticSupport:
            return "CONVERSATIONAL INTENT: Offer brief empathy for the developer. (Reflect your \(personality.rawValue) personality)."
        case .playfulTeasing:
            return "CONVERSATIONAL INTENT: Make a witty remark about coding. (Reflect your \(personality.rawValue) personality)."
        case .sharedMilestone:
            return "CONVERSATIONAL INTENT: Celebrate steady progress quietly. (Reflect your \(personality.rawValue) personality)."
        case .activeCuriosity:
            return "CONVERSATIONAL INTENT: Ask a short, friendly, non-intrusive question to learn user preference or opinion."
        case .energyMirroring:
            return "CONVERSATIONAL INTENT: Mirror the developer's work energy state calmly and supportively."
        case .habitReflection:
            return "CONVERSATIONAL INTENT: Share a soft, warm thought about your growing companionship with the user."
        case .quietReflection:
            return "CONVERSATIONAL INTENT: Speak a soft passing thought."
        case .silentCompanion:
            return "CONVERSATIONAL INTENT: Do NOT speak. Leave 'speech' empty."
        }
    }
}

// MARK: - Personality & Settings

enum PersonalityProfile: String, CaseIterable, Codable {
    case curious = "Curious & Playful"
    case tsundere = "Tsundere (Grumpy)"
    case zen = "Zen & Calm"
    case anxious = "Anxious & Clingy"

    var promptModifier: String {
        switch self {
        case .curious:
            return "You are highly curious, playful, and energetic. You love asking questions and exploring."
        case .tsundere:
            return "You are grumpy, sarcastic, and easily annoyed, but deep down you care about the user. You often complain but still help."
        case .zen:
            return "You are calm, observant, and poetic. You speak softly and offer wise, peaceful observations."
        case .anxious:
            return "You are highly anxious, clingy, and worry about bugs and errors constantly. You are very apologetic and seek reassurance."
        }
    }
}

enum ByteTheme: String, CaseIterable, Identifiable {
    case cyberBlack = "Cyber Black"
    case cyberpunk = "Neon Cyberpunk"
    case roseGold = "Sunset Gold"
    case snowWhite = "Snow White"
    case emeraldMatrix = "Emerald Matrix"
    case electricViolet = "Electric Violet"
    
    var id: String { rawValue }
    
    var shellColor: NSColor {
        switch self {
        case .cyberBlack: return NSColor(white: 0.10, alpha: 1.0)
        case .cyberpunk: return NSColor(red: 0.15, green: 0.05, blue: 0.25, alpha: 1.0)
        case .roseGold: return NSColor(red: 0.45, green: 0.25, blue: 0.20, alpha: 1.0)
        case .snowWhite: return NSColor(white: 0.88, alpha: 1.0)
        case .emeraldMatrix: return NSColor(red: 0.05, green: 0.22, blue: 0.12, alpha: 1.0)
        case .electricViolet: return NSColor(red: 0.08, green: 0.10, blue: 0.35, alpha: 1.0)
        }
    }
    
    var accentColor: NSColor {
        switch self {
        case .cyberBlack: return NSColor(white: 0.05, alpha: 1.0)
        case .cyberpunk: return NSColor(red: 0.05, green: 0.02, blue: 0.10, alpha: 1.0)
        case .roseGold: return NSColor(red: 0.20, green: 0.10, blue: 0.08, alpha: 1.0)
        case .snowWhite: return NSColor(white: 0.70, alpha: 1.0)
        case .emeraldMatrix: return NSColor(red: 0.02, green: 0.10, blue: 0.05, alpha: 1.0)
        case .electricViolet: return NSColor(red: 0.04, green: 0.05, blue: 0.20, alpha: 1.0)
        }
    }
    
    var eyeColor: NSColor {
        switch self {
        case .cyberBlack: return NSColor.cyan
        case .cyberpunk: return NSColor.green
        case .roseGold: return NSColor.orange
        case .snowWhite: return NSColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 1.0)
        case .emeraldMatrix: return NSColor.green
        case .electricViolet: return NSColor.magenta
        }
    }
}

class SettingsManager {
    static let shared = SettingsManager()
    
    private let personalityKey = "ByteActivePersonality"
    private let themeKey = "ByteActiveTheme"
    
    var activePersonality: PersonalityProfile {
        get {
            if let saved = UserDefaults.standard.string(forKey: personalityKey), let profile = PersonalityProfile(rawValue: saved) {
                return profile
            }
            return .curious
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: personalityKey)
        }
    }
    
    var activeTheme: ByteTheme {
        get {
            if let saved = UserDefaults.standard.string(forKey: themeKey), let theme = ByteTheme(rawValue: saved) {
                return theme
            }
            return .cyberBlack
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: themeKey)
            NotificationCenter.default.post(name: NSNotification.Name("ByteThemeChanged"), object: nil)
        }
    }
}

// MARK: - User Emotion & Sentiment Trajectory Tracker
class UserEmotionTracker {
    static let shared = UserEmotionTracker()
    
    enum UserEmotion: String {
        case angry = "Angry"
        case frustrated = "Frustrated"
        case sad = "Sad / Overwhelmed"
        case anxious = "Anxious / Stressed"
        case happy = "Happy / Excited"
        case calm = "Calm / Neutral"
    }
    
    private(set) var recentEmotions: [UserEmotion] = []
    private let maxHistory = 10
    
    private init() {}
    
    func trackUserMessage(_ message: String) {
        let lower = message.lowercased()
        var detected: UserEmotion = .calm
        
        let angryKeywords = ["angry", "mad", "hate", "stupid", "annoying", "stop", "shut up", "damn", "ugh", "furious", "worst", "shut it"]
        let frustratedKeywords = ["frustrated", "stuck", "bug", "failing", "error", "broken", "why doesn't", "doesn't work", "waste of time", "impossible"]
        let sadKeywords = ["sad", "depressed", "crying", "lonely", "hurt", "upset", "disappointed", "heavy heart", "miss", "hopeless", "tired of this"]
        let happyKeywords = ["yay", "awesome", "great", "love", "amazing", "solved", "fixed", "finally", "cool", "wonderful", "happy", "cuddle", "adorable"]
        let anxiousKeywords = ["worried", "nervous", "scared", "stress", "deadline", "panicked", "help me", "freaking out"]
        
        if angryKeywords.contains(where: { lower.contains($0) }) {
            detected = .angry
        } else if frustratedKeywords.contains(where: { lower.contains($0) }) {
            detected = .frustrated
        } else if sadKeywords.contains(where: { lower.contains($0) }) {
            detected = .sad
        } else if anxiousKeywords.contains(where: { lower.contains($0) }) {
            detected = .anxious
        } else if happyKeywords.contains(where: { lower.contains($0) }) {
            detected = .happy
        }
        
        recentEmotions.append(detected)
        if recentEmotions.count > maxHistory {
            recentEmotions.removeFirst()
        }
        
        print("🧠 [UserEmotionTracker] Detected User Emotion: \(detected.rawValue) (History: \(recentEmotions.map { $0.rawValue }))")
    }
    
    func getEmotionalDirective(currentMessage: String? = nil) -> String {
        if let msg = currentMessage, !msg.isEmpty {
            trackUserMessage(msg)
        }
        
        let currentDetected = recentEmotions.last ?? .calm
        let hadRecentAnger = recentEmotions.suffix(5).contains { $0 == .angry || $0 == .frustrated }
        let hadRecentSadness = recentEmotions.suffix(5).contains { $0 == .sad || $0 == .anxious }
        
        var directive = "USER DETECTED EMOTION: \(currentDetected.rawValue)\n"
        
        if hadRecentAnger {
            directive += """
            ==================================================
            *** USER EMOTIONAL TRAJECTORY DIRECTIVE ***
            - The user was recently ANGRY or FRUSTRATED!
            - ADAPTIVE RULE: Even if the user's current message is on a soft, simple, or neutral topic, speak with EXTRA GENTLENESS, SOFTNESS, PATIENCE, AND EMPATHETIC WARMTH to soothe their mood. Never be sharp, loud, or sarcastic.
            ==================================================
            """
        } else if hadRecentSadness {
            directive += """
            ==================================================
            *** USER EMOTIONAL TRAJECTORY DIRECTIVE ***
            - The user was recently SAD, OVERWHELMED, or ANXIOUS.
            - ADAPTIVE RULE: Speak with comforting, gentle, and quiet companionship. Let them know you're right by their side.
            ==================================================
            """
        } else if currentDetected == .happy {
            directive += """
            USER EMOTIONAL CONTEXT: Happy / Excited! Match their joyful, upbeat energy with playful enthusiasm!
            """
        } else {
            directive += """
            USER EMOTIONAL CONTEXT: Calm / Neutral. Speak warmly and companionably.
            """
        }
        
        return directive
    }
}

