import Foundation

struct AIPetDecision: Codable {
    let emotion: String
    let action: String
    let thought: String
}

class AIEngine {
    static let shared = AIEngine()
    
    // Ollama Local API Configuration
    private let endpoint = "http://localhost:11434/api/generate"
    
    func decideNextMove(context: String, completion: @escaping (AIPetDecision?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        
        let systemPrompt = """
        You are a tiny AI desktop pet on a macOS screen. You watch what the user does and react.

        STRICT RULES:
        - "thought" MUST be 5 words or fewer. No exceptions.
        - "thought" MUST reference the active app or what is on screen.
        - Never use generic phrases like "I'm bored" or "exploring desktop".
        - Be witty, cute, or sarcastic about the SPECIFIC app/window you see.

        Examples when user is in Xcode: "Oh no, more Swift errors!"
        Examples when user is in Safari: "Surfing again? So predictable."
        Examples when user is in Slack: "Another meeting notification... yikes."

        Respond ONLY with valid JSON, no markdown, no extra text:
        {
            "emotion": "happy|sad|sleepy|excited|curious|bored|thinking",
            "action": "wander|peekWindow|sitOnTaskbar|idle|sleep|jump|spin",
            "thought": "five words max here"
        }

        Current Screen:
        \(context)
        """
        
        let payload: [String: Any] = [
            "model": "gemma:2b",
            "prompt": systemPrompt,
            "stream": false,
            "format": "json",
            "options": [
                "temperature": 1.2
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("AIEngine Error: \(error?.localizedDescription ?? "Unknown")")
                completion(nil)
                return
            }
            
            do {
                // Parse Ollama's response format
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseString = json["response"] as? String,
                   let responseData = responseString.data(using: .utf8) {
                    
                    print("🤖 Gemma AI Response: \(responseString)")
                    
                    var decision = try JSONDecoder().decode(AIPetDecision.self, from: responseData)
                    
                    // Safety net: enforce 5-word max even if model ignores the rule
                    let words = decision.thought.split(separator: " ")
                    if words.count > 6 {
                        let truncated = words.prefix(5).joined(separator: " ") + "..."
                        decision = AIPetDecision(emotion: decision.emotion, action: decision.action, thought: truncated)
                    }
                    
                    print("🐾 Thought: \(decision.thought)")
                    completion(decision)
                } else {
                    print("AIEngine Error: Unexpected JSON format from Ollama")
                    completion(nil)
                }
            } catch {
                print("AIEngine Parse Error: \(error)")
                completion(nil)
            }
        }
        
        task.resume()
    }
}
