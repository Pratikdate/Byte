import Foundation
import CoreGraphics

/// Central coordinator for WHEN and HOW Byte speaks.
/// Replaces scattered random `requestLLMAction()` triggers with one attention-aware gate.
///
/// Three jobs:
///   1. Read the USER's attention state (focused / idle / away / just-returned).
///   2. Gate every speech impulse through `shouldSpeak(_:)` so Byte stays quiet when ignored.
///   3. Thread the conversation so the LLM stops repeating itself.
class InteractionDirector {
    static let shared = InteractionDirector()

    // MARK: - User Attention Model

    enum AttentionState {
        case engaged     // interacted with Byte very recently → fully responsive
        case active      // using the computer, present → normal ambient
        case idle        // no input 30s–5m → sparse, quiet
        case away        // no input > 5m → silent
        case returning   // input arrived after being away → one warm greeting
    }

    /// What Byte should do when it wants to talk.
    enum SpeechTrigger {
        case userDirected   // user clicked/spoke to Byte — always answer
        case reactive       // meaningful event: new file, app switch, return, startle
        case ambient        // idle filler / flavor text — lowest priority
    }

    // MARK: - Internal timing

    private var lastSpokeAt: Date = .distantPast
    private var wasAwayLastCheck = false
    private var pendingReturnGreeting = false

    // Minimum silence between utterances, per trigger class (seconds)
    private let ambientMinGap: TimeInterval = 18
    private let reactiveMinGap: TimeInterval = 5

    // MARK: - Conversation thread (fed to the LLM so it remembers what it just said)

    private struct Turn {
        let speaker: String   // "User" or "Byte"
        let text: String
    }
    private var thread: [Turn] = []
    private let maxThread = 8

    // MARK: - Attention

    /// Seconds since the user last touched keyboard/mouse anywhere on the system.
    private func systemIdleTime() -> TimeInterval {
        return CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    /// Seconds since the user last interacted with Byte directly (click / talk).
    private func byteInteractionRecency() -> TimeInterval {
        return DialogueContextTracker.shared.secondsSinceInteraction()
    }

    /// Current read on the user. Also latches a one-shot "returning" state.
    func currentAttention() -> AttentionState {
        let idle = systemIdleTime()
        let byteRecency = byteInteractionRecency()

        // Detect return-from-away transition (edge trigger).
        let isAwayNow = idle > 300
        if wasAwayLastCheck && !isAwayNow {
            pendingReturnGreeting = true
        }
        wasAwayLastCheck = isAwayNow

        if pendingReturnGreeting { return .returning }
        if byteRecency < 20 { return .engaged }
        if isAwayNow { return .away }
        if idle > 30 { return .idle }
        return .active
    }

    /// Consume the one-shot returning flag (call after Byte greets on return).
    func consumeReturnGreeting() {
        pendingReturnGreeting = false
    }

    // MARK: - User-Centric Engagement Throttle
    // Rule 1: Max 3 unprompted statements without user reply -> 1 minute pause.
    // Rule 2: If 1-minute pause happens 2 times in a row -> Stop completely until user engages.

    private(set) var unpromptedCount = 0
    private(set) var strikeCount = 0
    private(set) var isMutedUntilUserEngages = false
    private(set) var pauseUntilTime: Date = .distantPast

    func resetEngagementThrottle() {
        unpromptedCount = 0
        strikeCount = 0
        isMutedUntilUserEngages = false
        pauseUntilTime = .distantPast
    }

    // MARK: - The Speech Gate

    /// Single funnel: should Byte speak right now for this trigger?
    func shouldSpeak(_ trigger: SpeechTrigger) -> Bool {
        let sinceLastSpoke = Date().timeIntervalSince(lastSpokeAt)
        let attention = currentAttention()

        switch trigger {
        case .userDirected:
            // The user asked. Reset throttle counters immediately and answer.
            resetEngagementThrottle()
            return true

        case .reactive, .ambient:
            // 1. If 2 strikes reached, Byte stops speaking completely until user engages
            if isMutedUntilUserEngages {
                return false
            }

            // 2. Check if currently in 1-minute pause penalty
            if Date() < pauseUntilTime {
                return false
            }

            if trigger == .reactive {
                if attention == .away { return false }
                return sinceLastSpoke >= reactiveMinGap
            } else { // .ambient
                switch attention {
                case .engaged, .active:
                    guard sinceLastSpoke >= ambientMinGap else { return false }
                    return Double.random(in: 0...1) < 0.50
                case .returning:
                    return true
                case .idle, .away:
                    return false
                }
            }
        }
    }

    /// Record that Byte just spoke (starts the min-gap clock).
    func noteSpoke(_ text: String, trigger: SpeechTrigger = .ambient) {
        lastSpokeAt = Date()
        recordByteTurn(text)

        if trigger != .userDirected {
            unpromptedCount += 1
            print("[InteractionDirector] Unprompted speech count: \(unpromptedCount)/6")

            if unpromptedCount >= 6 {
                unpromptedCount = 0
                pauseUntilTime = Date().addingTimeInterval(30)
                print("[InteractionDirector] 6 unprompted statements reached. Enforcing short 30-second cooldown.")
            }
        }
    }

    // MARK: - Conversation Threading

    func recordUserTurn(_ text: String) {
        guard !text.isEmpty else { return }
        resetEngagementThrottle()
        thread.append(Turn(speaker: "User", text: text))
        trimThread()
    }

    private func recordByteTurn(_ text: String) {
        guard !text.isEmpty else { return }
        thread.append(Turn(speaker: "Byte", text: text))
        trimThread()
    }

    private func trimThread() {
        if thread.count > maxThread {
            thread.removeFirst(thread.count - maxThread)
        }
    }

    /// Formatted recent conversation for the LLM prompt (empty string if none).
    func conversationContext() -> String {
        guard !thread.isEmpty else { return "" }
        var out = "RECENT CONVERSATION (oldest first — continue it, do NOT repeat yourself):\n"
        for turn in thread {
            out += "\(turn.speaker): \(turn.text)\n"
        }
        return out
    }

    /// Openers Byte has used recently, so the prompt can forbid reusing them.
    func recentOpeners() -> [String] {
        return thread
            .filter { $0.speaker == "Byte" }
            .suffix(5)
            .map { turn in
                let words = turn.text.split(separator: " ").prefix(3)
                return words.joined(separator: " ")
            }
    }

    /// A short directive describing how present the user is — steers tone.
    func attentionDirective() -> String {
        switch currentAttention() {
        case .engaged:
            return "The user is actively engaging with you. Be warm and present."
        case .active:
            return "The user is working nearby. A brief, light remark is fine."
        case .idle:
            return "The user has been quiet a while. Keep it soft and short, or say nothing."
        case .away:
            return "The user is away. Stay silent unless something truly needs saying."
        case .returning:
            return "The user just came back after being away. Greet them warmly, once."
        }
    }
}
