import Foundation

class ReflectionEngine {
    static let shared = ReflectionEngine()
    
    private var isReflecting = false
    
    private init() {}
    
    /// Triggered during idle/sleep times. Reads recent logs and extracts new behavioral rules.
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
        
        // We use generateComment because it's a simple text completion without action parsing
        AIEngine.shared.provider.generateComment(systemPrompt: prompt) { response in
            self.isReflecting = false
            
            guard let response = response else {
                completion(false)
                return
            }
            
            let pattern = "\\[(?i)RULE:\\s*(.*?)\\]"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count)) {
                if let range = Range(match.range(at: 1), in: response) {
                    let rule = String(response[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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
