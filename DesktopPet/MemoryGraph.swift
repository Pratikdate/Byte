import Foundation

struct MemoryFact: Codable, Equatable {
    let subject: String
    let predicate: String
    let object: String
    
    var description: String {
        return "\(subject) \(predicate) \(object)"
    }
}

class MemoryGraph {
    static let shared = MemoryGraph()
    
    private var facts: [MemoryFact] = []
    
    private var fileURL: URL {
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return currentDir.appendingPathComponent("memory_graph.json")
    }
    
    private init() {
        loadMemories()
    }
    
    func addFact(subject: String, predicate: String, object: String) {
        let newFact = MemoryFact(subject: subject, predicate: predicate, object: object)
        if !facts.contains(newFact) {
            facts.append(newFact)
            saveMemories()
        }
    }
    
    func addBehavioralRule(_ rule: String) {
        addFact(subject: "Rule", predicate: "must", object: rule)
    }
    
    func getAllFactsString() -> String {
        if facts.isEmpty { return "None" }
        return facts.map { $0.description }.joined(separator: ", ")
    }
    
    /// Returns only facts that are about the User (filters out Byte's internal system rules)
    func getUserFactsString() -> String {
        let userFacts = facts.filter { fact in
            let sub = fact.subject.lowercased()
            // Exclude system rules like "Action: wander", "Emotion: happy", "Byte", "Humans", "Active Windows", "Rule"
            if sub.starts(with: "action:") || sub.starts(with: "emotion:") || sub == "byte" || sub == "humans" || sub == "active windows" || sub == "taskbar (dock)" || sub == "mouse cursor" || sub == "the desktop" || sub == "explore loops" || sub == "rule" {
                return false
            }
            return true
        }
        
        if userFacts.isEmpty { return "No personal facts known yet." }
        return userFacts.map { $0.description }.joined(separator: ", ")
    }
    
    /// Returns only behavioral rules that the AI must follow
    func getBehavioralRulesString() -> String {
        let ruleFacts = facts.filter { fact in
            return fact.subject.lowercased() == "rule" || fact.subject.lowercased() == "byte"
        }
        
        if ruleFacts.isEmpty { return "No specific behavioral rules." }
        return ruleFacts.map { "- \($0.description)" }.joined(separator: "\n")
    }
    
    private func saveMemories() {
        let factsCopy = facts
        let url = fileURL
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(factsCopy)
                try data.write(to: url)
                print("Saved memories to \(url.path)")
            } catch {
                print("Failed to save memory graph: \(error)")
            }
        }
    }
    
    private func loadMemories() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            facts = try JSONDecoder().decode([MemoryFact].self, from: data)
            print("Loaded \(facts.count) memories.")
        } catch {
            print("Failed to load memory graph: \(error)")
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
        AIEngine.shared.provider.generateComment(systemPrompt: prompt) { response in
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
