import Foundation

/// Tracks dialogue context per emotion to prevent repetition & enforce silence periods
class DialogueContextTracker {
    static let shared = DialogueContextTracker()

    // Per-emotion script rotation (up to 5 variants each)
    private var emotionScripts: [String: [String]] = [:]

    // Dialogue history tagged with emotion + timestamp
    private struct DialogueLine {
        let text: String
        let emotion: String
        let timestamp: Date
    }
    private var history: [DialogueLine] = []
    private let maxHistorySize = 30

    // Silence tracking
    private var lastInteractionTime: Date = Date()
    private var isSilenced = false

    init() {
        initializeScriptVariants()
    }

    /// Load 4-5 script variants per emotion to rotate through
    private func initializeScriptVariants() {
        emotionScripts = [
            "excited": [
                "Ooh what's that!?",
                "Something's happening!",
                "Whoa whoa whoa!",
                "Did you see that!?",
                "Let's goooo!"
            ],
            "curious": [
                "Hmm, interesting...",
                "What is this?",
                "I wonder...",
                "Tell me more?",
                "So curious..."
            ],
            "sleepy": [
                "Yawn...",
                "So tired...",
                "Maybe sleep soon?",
                "Eyes closing...",
                "Zzzzz..."
            ],
            "sad": [
                "Things aren't great...",
                "Feeling quiet today...",
                "A little down...",
                "Lonely, maybe?",
                "Wish you were here..."
            ],
            "annoyed": [
                "Really?",
                "Stop that.",
                "Enough!",
                "Go away.",
                "Ugh."
            ],
            "happy": [
                "This is great!",
                "Love it!",
                "Woohoo!",
                "So happy!",
                "Best day ever!"
            ],
            "bored": [
                "Nothing to do...",
                "Waiting...",
                "Kinda boring.",
                "Is it time yet?",
                "Sigh..."
            ]
        ]
    }

    /// Register user interaction (click, speech, etc)
    func recordInteraction() {
        lastInteractionTime = Date()
        isSilenced = false
    }

    /// Seconds since the user last interacted with Byte directly.
    func secondsSinceInteraction() -> TimeInterval {
        return Date().timeIntervalSince(lastInteractionTime)
    }

    /// Add dialogue to history tagged with emotion
    func recordDialogue(_ text: String, emotion: String) {
        let line = DialogueLine(text: text, emotion: emotion, timestamp: Date())
        history.append(line)
        if history.count > maxHistorySize {
            history.removeFirst()
        }
    }

    /// Check if Byte should be silent (user inactive > threshold)
    func shouldBeSilent() -> Bool {
        let inactiveSeconds = Date().timeIntervalSince(lastInteractionTime)

        // Silent after 5 minutes of inactivity
        if inactiveSeconds > 300 {
            isSilenced = true
            return true
        }

        // Partially quiet after 30 seconds (fewer unsolicited comments)
        return false
    }

    /// Check if actively silent (user away > 5 minutes)
    func isActivelySilent() -> Bool {
        let inactiveSeconds = Date().timeIntervalSince(lastInteractionTime)
        return inactiveSeconds > 300 && isSilenced
    }

    /// Get inactivity level: 0-1 (0=just interacted, 1=max silence)
    func inactivityLevel() -> Float {
        let seconds = Float(Date().timeIntervalSince(lastInteractionTime))
        let maxSeconds: Float = 300 // 5 minutes
        return min(seconds / maxSeconds, 1.0)
    }

    /// Reduce unsolicited comments when idle (30s-5m range)
    func shouldSkipUnsolicited() -> Bool {
        let inactiveSeconds = Date().timeIntervalSince(lastInteractionTime)
        // Skip 80% of ambient dialogue after 30s
        if inactiveSeconds > 30 && inactiveSeconds < 300 {
            return Double.random(in: 0...1) < 0.8
        }
        return false
    }

    /// Get next script variant for emotion (rotates through 5)
    func getScriptVariant(for emotion: String) -> String? {
        guard let scripts = emotionScripts[emotion.lowercased()], !scripts.isEmpty else {
            return nil
        }

        // Count how many times this emotion was used in last 5 lines
        let recentEmotions = history.suffix(5).filter { $0.emotion.lowercased() == emotion.lowercased() }
        let index = recentEmotions.count % scripts.count

        return scripts[index]
    }

    /// Check if dialogue would repeat too soon
    func isValidNewDialogue(_ candidate: String, emotion: String) -> Bool {
        let candidateWords = Set(candidate.lowercased().split(separator: " "))

        // Check against last 5 lines of same emotion
        let recentSameEmotion = history.suffix(5).filter { $0.emotion.lowercased() == emotion.lowercased() }

        for prev in recentSameEmotion {
            let prevWords = Set(prev.text.lowercased().split(separator: " "))
            let overlap = candidateWords.intersection(prevWords).count
            let maxWords = max(candidateWords.count, prevWords.count)

            // Reject if >60% word overlap
            if maxWords > 0 && Float(overlap) / Float(maxWords) > 0.6 {
                return false
            }
        }

        // Exact duplicate check
        for prev in recentSameEmotion {
            if candidate.lowercased().trimmingCharacters(in: .punctuationCharacters)
                == prev.text.lowercased().trimmingCharacters(in: .punctuationCharacters) {
                return false
            }
        }

        return true
    }

    /// Get contextual dialogue suggestion (used as fallback when LLM is slow)
    func getSilenceAppropriateResponse() -> String {
        let level = inactivityLevel()

        if level < 0.2 {
            return "Anything to explore?"
        } else if level < 0.5 {
            return "Keeping watch..."
        } else if level < 0.8 {
            return "Quiet moment..."
        } else {
            return ""  // Actively silent
        }
    }
}
