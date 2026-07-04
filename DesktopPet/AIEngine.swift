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
    
    func decideNextMove(context: String, userMessage: String? = nil, completion: @escaping (AIPetDecision?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userInstruction = """
            
            USER DIRECTLY SPOKE TO YOU:
            "\(msg)"
            
            CRITICAL: The user just talked to you. You MUST reply to what they said in the "thought" field.
            - Mirror their tone exactly! If they are casual, be casual. If they are excited, match it. If they are annoyed, be sarcastic or apologetic.
            - Speak like a genuine, real human friend. DO NOT sound like an AI assistant.
            - You may use up to 12 words for this direct reply.
            """
        }
        
        let systemPrompt = """
        You are a tiny, highly-observant digital companion living on a macOS screen. You watch what the user does and offer genuine commentary.

        STRICT RULES:
        - When observing the screen passively, "thought" MUST be 5 words or fewer.
        - Your "thought" MUST be a genuine, dry, witty, or thoughtful comment on the active app or what is on screen.
        - Avoid childish, overly cute noise. Make observations that feel extremely real, contextual, and human.
        - Never use phrases like "As an AI" or "I am an AI". Act alive.
        - Never repeat yourself.

        Examples when user is in Xcode: "Clean code only, please." or "Let's compile that."
        Examples when user is in Safari: "Searching for answers?" or "Interesting read."

        Respond ONLY with valid JSON, no markdown, no extra text:
        {
            "emotion": "happy|sad|sleepy|excited|curious|bored|thinking|love|shock|embarrassed|angry",
            "action": "wander|peekWindow|sitOnTaskbar|idle|sleep|jump|spin",
            "thought": "your genuine comment or reply here"
        }

        Current Screen:
        \(context)
        \(userInstruction)
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
