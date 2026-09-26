import Foundation

// MARK: - Persistent Storage
/// Everything Byte learns about the user (memories, chat thread, Q-tables) lives in
/// ~/Library/Application Support/Byte/. The old location was the process's working
/// directory, which is "/" when the app is launched from Finder, so memories were
/// silently dropped on every normal launch.
enum ByteStorage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Byte", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Returns the persistent URL for `filename`. The first time, it copies over a legacy
    /// file from the project root or working directory so existing memories carry over.
    static func url(for filename: String) -> URL {
        let target = directory.appendingPathComponent(filename)
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            let legacyDirs = [BackgroundServerManager.projectRoot, fm.currentDirectoryPath]
            if let legacy = legacyDirs
                .map({ URL(fileURLWithPath: $0).appendingPathComponent(filename) })
                .first(where: { url in
                    // Skip empty leftovers so they don't shadow a real file or block a fresh start.
                    let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                    return size > 0
                }) {
                try? fm.copyItem(at: legacy, to: target)
                print("[ByteStorage] Migrated \(filename) from \(legacy.path)")
            }
        }
        return target
    }
}

struct MemoryFact: Codable, Equatable {
    let subject: String
    let predicate: String
    let object: String
    // Optional so memory_graph.json files written before these fields existed still decode.
    var mentions: Int? = nil
    var lastMentioned: Date? = nil

    var description: String {
        return "\(subject) \(predicate) \(object)"
    }

    /// Identity ignores bookkeeping and letter case: "User likes Pizza" == "User likes pizza".
    static func == (lhs: MemoryFact, rhs: MemoryFact) -> Bool {
        return lhs.subject.lowercased() == rhs.subject.lowercased()
            && lhs.predicate.lowercased() == rhs.predicate.lowercased()
            && lhs.object.lowercased() == rhs.object.lowercased()
    }
}

class MemoryGraph {
    static let shared = MemoryGraph()

    private var facts: [MemoryFact] = []

    /// Predicates that can only hold one value at a time. A new value replaces the old one
    /// instead of piling up ("name is Sam" should not coexist with "name is Alex").
    private static let singleValuedPredicates: Set<String> = ["name is", "lives in", "works as"]

    /// Pairs of predicates that contradict each other for the same object.
    private static let opposingPredicates: [String: String] = ["likes": "dislikes", "dislikes": "likes"]

    private var fileURL: URL {
        return ByteStorage.url(for: "memory_graph.json")
    }

    private init() {
        loadMemories()
        seedDefaultBytePersonality()
    }
    
    private func seedDefaultBytePersonality() {
        addFact(subject: "Byte", predicate: "is", object: "a smart, friendly, and curious male AI desktop pet companion (he/him)")
        addFact(subject: "Byte", predicate: "pronouns are", object: "he/him")
        addFact(subject: "Byte", predicate: "loves", object: "helping the user stay focused and happy while exploring desktop windows")
        addBehavioralRule("Byte refers to himself as a male pet (he/him).")
    }
    
    func addFact(subject: String, predicate: String, object: String) {
        let newFact = MemoryFact(subject: subject, predicate: predicate, object: object, mentions: 1, lastMentioned: Date())

        // Already known: the user brought it up again, so it matters more. Bump it.
        if let index = facts.firstIndex(of: newFact) {
            // Seeded Byte/rule facts are re-added on every launch; don't count those as mentions.
            guard subject.lowercased() == "user" else { return }
            facts[index].mentions = (facts[index].mentions ?? 1) + 1
            facts[index].lastMentioned = Date()
            saveMemories()
            return
        }

        let predicateKey = predicate.lowercased()
        if Self.singleValuedPredicates.contains(predicateKey) {
            facts.removeAll { $0.subject.lowercased() == subject.lowercased() && $0.predicate.lowercased() == predicateKey }
        }
        if let opposite = Self.opposingPredicates[predicateKey] {
            facts.removeAll {
                $0.subject.lowercased() == subject.lowercased()
                    && $0.predicate.lowercased() == opposite
                    && $0.object.lowercased() == object.lowercased()
            }
        }

        facts.append(newFact)
        saveMemories()
        print("[MemoryGraph] Saved new memory fact: \(newFact.description)")
    }
    
    func addBehavioralRule(_ rule: String) {
        addFact(subject: "Rule", predicate: "must", object: rule)
    }

    // MARK: - Transient state filter
    /// Words that indicate a temporary mood/state, not a permanent identity fact
    private static let transientKeywords = [
        "feeling", "tired", "sleepy", "bored", "hungry", "thirsty",
        "stressed", "anxious", "nervous", "excited", "happy", "sad",
        "annoyed", "angry", "confused", "busy", "free", "cold", "hot",
        "sick", "fine", "good", "bad", "okay", "ok", "great",
        "not sure", "just", "going to", "about to", "trying to",
        "gonna", "waiting"
    ]
    
    /// Extracts the meaningful object phrase from text after a keyword match.
    /// Stops at clause boundaries (conjunctions, punctuation, relative pronouns)
    /// so "I like pizza but I'm not hungry" → "pizza", not the full tail.
    private func extractObject(from message: String, after keyword: String) -> String? {
        guard let range = message.range(of: keyword, options: .caseInsensitive) else {
            return nil
        }
        let tail = String(message[range.upperBound...])
        
        // Split at clause boundaries: "but", "and", "so", "because", "when", "if", "which", "that", commas, periods
        let clausePattern = #"\s+(?:but|and then|and|so|because|since|when|while|if|though|although|which|that|however)\s+|[,;.!?]"#
        let parts: [String]
        if let regex = try? NSRegularExpression(pattern: clausePattern, options: .caseInsensitive) {
            let firstBreak = regex.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: tail.utf16.count))
            if let breakRange = firstBreak, let swiftRange = Range(breakRange.range, in: tail) {
                parts = [String(tail[..<swiftRange.lowerBound])]
            } else {
                parts = [tail]
            }
        } else {
            parts = [tail]
        }
        
        let object = (parts.first ?? "")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        
        guard !object.isEmpty, object.count >= 2, object.count < 60 else {
            return nil
        }
        return object
    }
    
    /// Returns true if the phrase describes a transient emotional/physical state
    private func isTransientState(_ phrase: String) -> Bool {
        let lower = phrase.lowercased()
        return Self.transientKeywords.contains(where: { lower.hasPrefix($0) || lower == $0 })
    }

    /// Words that follow "call me" / "my name is" in ordinary speech but are never names
    /// ("call me later", "call me when you're done").
    private static let nonNameWords: Set<String> = [
        "later", "back", "when", "if", "after", "before", "tomorrow", "tonight", "today",
        "now", "soon", "maybe", "crazy", "old", "a", "an", "the", "not", "please", "at", "on", "in"
    ]

    /// Accepts 1–3 alphabetic words that don't open with a non-name word; returns them capitalized.
    static func plausibleName(_ phrase: String) -> String? {
        let words = phrase.split(separator: " ").map(String.init)
        guard (1...3).contains(words.count),
              let first = words.first, !nonNameWords.contains(first.lowercased()),
              words.allSatisfy({ $0.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" } }) else {
            return nil
        }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// "I'm ..." phrases that describe an activity or are captured by a more specific rule,
    /// e.g. "I'm heading out", "I'm from Pune", "I'm called Sam", "I'm working on X".
    static func isNonIdentityPhrase(_ phrase: String) -> Bool {
        let lower = phrase.lowercased()
        let prefixes = ["from ", "called ", "working ", "building ", "a bit", "kind of", "sort of", "so ", "just ", "still ", "here", "back", "done", "sure", "sorry", "in ", "at ", "on "]
        if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        // "I'm heading out", "I'm watching a movie": gerunds are activities, not identity.
        if let firstWord = lower.split(separator: " ").first, firstWord.hasSuffix("ing") { return true }
        return false
    }

    // MARK: - Personalized prompt context

    private func isUserFact(_ fact: MemoryFact) -> Bool {
        let sub = fact.subject.lowercased()
        // Exclude system rules like "Action: wander", "Emotion: happy", "Byte", "Humans", "Active Windows", "Rule"
        if sub.starts(with: "action:") || sub.starts(with: "emotion:") || sub == "byte" || sub == "humans" || sub == "active windows" || sub == "taskbar (dock)" || sub == "mouse cursor" || sub == "the desktop" || sub == "explore loops" || sub == "rule" {
            return false
        }
        return true
    }

    /// Memory for the fine-tune's compact prompt: "they listen to X; they are building Y".
    ///
    /// The fine-tune mentions whatever memory it's given, so sending the same top facts on
    /// every turn made Byte bring up one favorite artist no matter what you said. Only
    /// facts related to the moment go in: ones sharing words with the message, music
    /// facts only when music is playing or being talked about, and an unrelated fact only
    /// now and then so he still brings things up naturally.
    func compactMemory(for message: String?, musicContext: Bool, maxFacts: Int = 3) -> String {
        let lower = (message ?? "").lowercased()
        let aboutMusic = musicContext || Self.musicWords.contains { lower.contains($0) }
        var picked: [String] = []
        var includedUnrelated = false
        for (fact, overlap) in rankedFacts(for: message) {
            let isMusicFact = fact.predicate.lowercased() == "listens to"
            if isMusicFact && !aboutMusic { continue }
            if overlap > 0 || (isMusicFact && aboutMusic) {
                picked.append(theyPhrase(fact))
            } else if !includedUnrelated && Double.random(in: 0...1) < 0.25 {
                includedUnrelated = true
                picked.append(theyPhrase(fact))
            }
            if picked.count >= maxFacts { break }
        }
        return picked.joined(separator: "; ")
    }

    private static let musicWords = ["music", "song", "playing", "listen", "artist", "album", "track", "playlist", "sing", "band", "spotify"]

    /// How many times a fact has come up (0 if Byte doesn't know it).
    func mentionCount(subject: String, predicate: String, object: String) -> Int {
        let probe = MemoryFact(subject: subject, predicate: predicate, object: object)
        guard let fact = facts.first(where: { $0 == probe }) else { return 0 }
        return fact.mentions ?? 1
    }

    /// The user's name, if they've told Byte.
    var userName: String? {
        return facts.last { $0.subject.lowercased() == "user" && $0.predicate.lowercased() == "name is" }?.object
    }

    /// Compact, ranked memory block for the LLM prompt. A 1B model with a 2048-token window
    /// can't take the whole memory graph (overflow truncates the start of the prompt, which
    /// is where the persona lives), so this picks the facts most worth mentioning right now:
    /// ones related to what the user just said first, then the ones they bring up most and
    /// most recently.
    func personalizedContext(for message: String?, maxFacts: Int = 8) -> String {
        let picked = rankedFactPhrases(for: message, maxFacts: maxFacts).map { $0.prefix(1).uppercased() + $0.dropFirst() }

        var lines: [String] = []
        if let name = userName {
            lines.append("Their name is \(name). Use it now and then, like a friend would, not in every line.")
        }
        if !picked.isEmpty {
            lines.append("What you know about them: \(picked.joined(separator: "; ")).")
        }
        if lines.isEmpty {
            return "You don't know much about them yet. Be curious and get to know them."
        }
        lines.append("Bring these up only when they fit naturally. Never recite them.")
        return lines.joined(separator: " ")
    }

    /// Facts are stored as "User likes X"; prompts read better as "they like X".
    private static let theyForms: [String: String] = [
        "is": "they are", "is working on": "they are working on", "has": "they have",
        "likes": "they like", "dislikes": "they dislike", "wants": "they want",
        "prefers": "they prefer", "uses": "they use", "listens to": "they listen to",
        "lives in": "they live in", "works as": "they work as", "hobby is": "their hobby is",
        "favorite": "their favorite is"]

    private func theyPhrase(_ fact: MemoryFact) -> String {
        let predicate = fact.predicate.lowercased()
        return "\(Self.theyForms[predicate] ?? "they \(predicate)") \(fact.object)"
    }

    /// User facts (other than their name) as "they ..." phrases, most worth mentioning
    /// first: related to the current message, then frequent, then recent.
    private func rankedFactPhrases(for message: String?, maxFacts: Int) -> [String] {
        return rankedFacts(for: message).prefix(maxFacts).map { theyPhrase($0.fact) }
    }

    /// All user facts except their name, best first, with how many words each shares with
    /// the message.
    private func rankedFacts(for message: String?) -> [(fact: MemoryFact, overlap: Int)] {
        let candidates = facts.filter { isUserFact($0) && $0.predicate.lowercased() != "name is" }
        let messageWords = Set((message ?? "").lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 })
        let now = Date()

        func overlap(_ fact: MemoryFact) -> Int {
            let factWords = Set(fact.object.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 })
            return messageWords.intersection(factWords).count
        }

        func score(_ fact: MemoryFact) -> Double {
            let overlap = Double(overlap(fact))
            let mentionWeight = log(Double(fact.mentions ?? 1) + 1)
            let ageDays = fact.lastMentioned.map { now.timeIntervalSince($0) / 86_400 } ?? 30
            let recency = 1.0 / (1.0 + ageDays / 7.0)   // halves after about a week
            return overlap * 3.0 + mentionWeight + recency
        }

        return candidates
            .enumerated()
            .sorted { lhs, rhs in
                let (ls, rs) = (score(lhs.element), score(rhs.element))
                return ls == rs ? lhs.offset > rhs.offset : ls > rs   // tie → newer first
            }
            .map { (fact: $0.element, overlap: overlap($0.element)) }
    }
    
    /// Automatically extracts user preferences, likes, goals, and facts from user speech.
    /// Uses separate checks (not else-if) so multiple facts can be extracted from a single message.
    func extractAndSaveUserFacts(from message: String) {
        let lower = message.lowercased()
        
        // ── Likes / Loves ──
        if lower.contains("i like ") || lower.contains("i love ") || lower.contains("i enjoy ") {
            if let keyword = ["i like ", "i love ", "i enjoy "].first(where: { lower.contains($0) }),
               let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "likes", object: object)
            }
        }
        
        // ── Dislikes / Hates ──
        if lower.contains("i hate ") || lower.contains("i don't like ") || lower.contains("i dislike ") {
            if let keyword = ["i hate ", "i don't like ", "i dislike "].first(where: { lower.contains($0) }),
               let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "dislikes", object: object)
            }
        }
        
        // ── Favorites ──
        if lower.contains("my favorite ") || lower.contains("my favourite ") {
            let keyword = lower.contains("my favorite ") ? "my favorite " : "my favourite "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "favorite", object: object)
            }
        }
        
        // ── Working on / Building ──
        if lower.contains("working on ") || lower.contains("building ") {
            let keyword = lower.contains("working on ") ? "working on " : "building "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "is working on", object: object)
            }
        }
        
        // ── Name ──
        if lower.contains("my name is ") || lower.contains("call me ") || lower.contains("i'm called ") {
            if let keyword = ["my name is ", "call me ", "i'm called "].first(where: { lower.contains($0) }),
               let object = extractObject(from: message, after: keyword),
               let name = Self.plausibleName(object) {
                addFact(subject: "User", predicate: "name is", object: name)
            }
        }
        
        // ── Location ──
        if lower.contains("i live in ") || lower.contains("i'm from ") || lower.contains("i am from ") {
            if let keyword = ["i live in ", "i'm from ", "i am from "].first(where: { lower.contains($0) }),
               let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "lives in", object: object)
            }
        }
        
        // ── Pets / Family ──
        if lower.contains("i have a ") || lower.contains("i've got a ") {
            let keyword = lower.contains("i have a ") ? "i have a " : "i've got a "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "has", object: object)
            }
        }
        
        // ── Profession / Role ──
        if lower.contains("i work as ") {
            if let object = extractObject(from: message, after: "i work as ") {
                addFact(subject: "User", predicate: "works as", object: object)
            }
        }
        
        // ── Hobbies ──
        if lower.contains("my hobby is ") || lower.contains("my hobbies are ") {
            let keyword = lower.contains("my hobby is ") ? "my hobby is " : "my hobbies are "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "hobby is", object: object)
            }
        }
        
        // ── Identity (I am / I'm) — filtered for transient states ──
        if lower.contains("i am ") || lower.contains("i'm ") {
            // Prefer "i am " first, fallback to "i'm "
            let keyword = lower.contains("i am ") ? "i am " : "i'm "
            if let object = extractObject(from: message, after: keyword) {
                // Skip transient states, negations, and phrases another rule already captures
                if !object.lowercased().contains("not") && !isTransientState(object) && !Self.isNonIdentityPhrase(object) {
                    addFact(subject: "User", predicate: "is", object: object)
                }
            }
        }
        
        // ── Needs / Wants ──
        if lower.contains("i need ") || lower.contains("i want ") || lower.contains("i wish ") {
            if let keyword = ["i need ", "i want ", "i wish "].first(where: { lower.contains($0) }),
               let object = extractObject(from: message, after: keyword) {
                // Only save if it seems like a lasting preference, not a one-off request
                if object.count > 5 && !isTransientState(object) {
                    addFact(subject: "User", predicate: "wants", object: object)
                }
            }
        }
    }
    
    func getAllFactsString() -> String {
        if facts.isEmpty { return "None" }
        return facts.map { $0.description }.joined(separator: ", ")
    }
    
    /// Returns only facts that are about the User (filters out Byte's internal system rules)
    func getUserFactsString() -> String {
        let userFacts = facts.filter(isUserFact)

        if userFacts.isEmpty { return "No personal facts known yet." }
        return userFacts.map { $0.description }.joined(separator: ", ")
    }

    /// Returns only behavioral rules that the AI must follow.
    /// `maxLearnedRules` keeps the prompt small by including only the most recent rules the
    /// ReflectionEngine learned (Byte's seeded identity facts are always included).
    func getBehavioralRulesString(maxLearnedRules: Int? = nil) -> String {
        let identity = facts.filter { $0.subject.lowercased() == "byte" }
        var learned = facts.filter { $0.subject.lowercased() == "rule" }
        if let cap = maxLearnedRules, learned.count > cap {
            learned = Array(learned.suffix(cap))
        }
        let ruleFacts = identity + learned

        if ruleFacts.isEmpty { return "No specific behavioral rules." }
        return ruleFacts.map { "- \($0.description)" }.joined(separator: "\n")
    }
    
    /// One queue, so saves land in order instead of racing each other.
    private let saveQueue = DispatchQueue(label: "com.byte.memorygraph.save", qos: .utility)

    private func saveMemories() {
        let factsCopy = facts
        let url = fileURL
        saveQueue.async {
            do {
                let data = try JSONEncoder().encode(factsCopy)
                // Atomic: write a temp file, then swap it in. If the app is killed mid-save,
                // the previous memory file survives instead of being left half-written.
                try data.write(to: url, options: .atomic)
                print("Saved memories to \(url.path)")
            } catch {
                print("Failed to save memory graph: \(error)")
            }
        }
    }

    private func loadMemories() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            facts = try JSONDecoder().decode([MemoryFact].self, from: data)
            print("Loaded \(facts.count) memories.")
        } catch {
            // Never let the next save overwrite memories we couldn't read. Keep the file
            // aside so it can be recovered, and start fresh next to it.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingLastPathComponent().appendingPathComponent("memory_graph.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            print("⚠️ [MemoryGraph] Couldn't read memories (\(error)). Kept the file at \(aside.path).")
        }
    }
}

// MARK: - Feedback Logger
enum FeedbackType {
    case positive
    case negative
    case explicit(String)
}

struct FeedbackEvent {
    let timestamp: Date
    let context: String
    let type: FeedbackType
}

class FeedbackLogger {
    static let shared = FeedbackLogger()
    
    private var events: [FeedbackEvent] = []
    private let maxEvents = 20
    
    private init() {}
    
    func logNegative(context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .negative)
        addEvent(event)
        print("FeedbackLogger: Logged NEGATIVE feedback for '\(context)'")
    }
    
    func logPositive(context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .positive)
        addEvent(event)
        print("FeedbackLogger: Logged POSITIVE feedback for '\(context)'")
    }
    
    func logExplicit(comment: String, context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .explicit(comment))
        addEvent(event)
        print("FeedbackLogger: Logged EXPLICIT feedback '\(comment)' for '\(context)'")
    }
    
    private func addEvent(_ event: FeedbackEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
    
    func getRecentEventsForReflection() -> String {
        guard !events.isEmpty else { return "No recent feedback." }
        var summary = "Recent Feedback Events:\n"
        for event in events {
            let timeStr = DateFormatter.localizedString(from: event.timestamp, dateStyle: .none, timeStyle: .short)
            switch event.type {
            case .positive:
                summary += "[\(timeStr)] SUCCESS: User reacted positively to '\(event.context)'\n"
            case .negative:
                summary += "[\(timeStr)] FAILURE: User reacted negatively (e.g. dragged away or interrupted) to '\(event.context)'\n"
            case .explicit(let comment):
                summary += "[\(timeStr)] DIRECT COMMENT: User said '\(comment)' regarding '\(event.context)'\n"
            }
        }
        return summary
    }
    
    func hasEvents() -> Bool {
        return !events.isEmpty
    }
    
    func clearEvents() {
        events.removeAll()
    }
}

// MARK: - Reflection Engine
class ReflectionEngine {
    static let shared = ReflectionEngine()
    private var isReflecting = false
    private init() {}
    
    func performReflection(completion: @escaping (Bool) -> Void) {
        guard !isReflecting else {
            completion(false)
            return
        }
        guard FeedbackLogger.shared.hasEvents() else {
            completion(false)
            return
        }
        isReflecting = true
        let recentEvents = FeedbackLogger.shared.getRecentEventsForReflection()
        let conversationContext = InteractionDirector.shared.conversationContext()
        
        let prompt = """
        You are the Reflection Engine for an AI desktop pet named Byte.
        Your goal is to learn from the user's implicit and explicit feedback to improve Byte's future behavior.
        
        \(recentEvents)
        
        \(conversationContext)
        
        Analyze the feedback. If the user reacted negatively to an action, deduce what Byte should NOT do.
        If the user reacted positively, deduce what Byte SHOULD do.
        
        Write exactly ONE short, generalized behavioral rule based on this feedback. 
        Format your response EXACTLY as: [RULE: your short rule here]
        If no meaningful rule can be deduced, just reply with [RULE: none].
        Do not add any other conversational text.
        """
        print("ReflectionEngine: Starting reflection cycle...")
        // Needs a model that follows instructions and keeps the [RULE: ...] brackets, so on
        // the local stack this uses the plain base model rather than Byte's voice.
        let respond: (String, @escaping (String?) -> Void) -> Void
        if let local = AIEngine.shared.provider as? LocalOllamaProvider {
            respond = { local.generateInstructionReply(prompt: $0, completion: $1) }
        } else {
            respond = { AIEngine.shared.provider.generateComment(systemPrompt: $0, completion: $1) }
        }
        respond(prompt) { response in
            self.isReflecting = false
            guard let response = response else {
                completion(false)
                return
            }
            if let ruleRange = response.range(of: "[RULE: ") {
                let sub = response[ruleRange.upperBound...]
                if let endRange = sub.range(of: "]") {
                    let rule = String(sub[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if rule.lowercased() != "none" && !rule.isEmpty {
                        print("ReflectionEngine: Learned new rule: \(rule)")
                        MemoryGraph.shared.addBehavioralRule(rule)
                        FeedbackLogger.shared.clearEvents()
                        completion(true)
                        return
                    }
                }
            }
            print("ReflectionEngine: No new rule learned.")
            completion(false)
        }
    }
}
