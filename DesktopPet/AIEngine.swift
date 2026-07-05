import Foundation

struct AIAgentDecision: Codable {
    let action: String
    let emotion: String
    let speech: String
    let store_memory: MemoryFact?
}

// MARK: - AI Provider Protocol
/// Allows swapping out the underlying AI engine (e.g. Local vs Cloud API)
protocol AIProvider {
    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void)
    func generateAgentDecision(systemPrompt: String, completion: @escaping (AIAgentDecision?) -> Void)
}

// MARK: - Gemini API Provider
class GeminiAPIProvider: AIProvider {
    private let apiKey: String
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void) {
        let urlString = "\(endpoint)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let payload: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": systemPrompt]]]
            ],
            "generationConfig": [
                "temperature": 0.9
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
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                    completion(cleaned)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
    
    func generateAgentDecision(systemPrompt: String, completion: @escaping (AIAgentDecision?) -> Void) {
        let urlString = "\(endpoint)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let payload: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": systemPrompt]]]
            ],
            "generationConfig": [
                "temperature": 0.8,
                "response_mime_type": "application/json"
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
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    
                    var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.hasPrefix("```json") {
                        cleanText.removeFirst(7)
                    } else if cleanText.hasPrefix("```") {
                        cleanText.removeFirst(3)
                    }
                    if cleanText.hasSuffix("```") {
                        cleanText.removeLast(3)
                    }
                    cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let data = cleanText.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        let decision = try decoder.decode(AIAgentDecision.self, from: data)
                        completion(decision)
                        return
                    }
                }
            } catch {
                print("Failed to decode Gemini JSON decision: \(error)")
            }
            completion(nil)
        }
        task.resume()
    }
}

// MARK: - Local Ollama Provider
class LocalOllamaProvider: AIProvider {
    private let endpoint = "http://localhost:11434/api/generate"
    private let modelName = "llama3.2"
    
    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": systemPrompt,
            "stream": false
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
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseText = json["response"] as? String {
                    let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                    completion(cleaned)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
    
    func generateAgentDecision(systemPrompt: String, completion: @escaping (AIAgentDecision?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": systemPrompt,
            "stream": false,
            "format": "json"
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
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseText = json["response"] as? String {
                    
                    var cleanText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.hasPrefix("```json") {
                        cleanText.removeFirst(7)
                    } else if cleanText.hasPrefix("```") {
                        cleanText.removeFirst(3)
                    }
                    if cleanText.hasSuffix("```") {
                        cleanText.removeLast(3)
                    }
                    cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let responseData = cleanText.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        let decision = try decoder.decode(AIAgentDecision.self, from: responseData)
                        completion(decision)
                        return
                    }
                }
            } catch {
                print("Failed to decode Ollama JSON decision: \(error)")
            }
            completion(nil)
        }
        task.resume()
    }
}

// MARK: - AI Engine
class AIEngine {
    static let shared = AIEngine()
    
    // Configure API Key here
    var provider: AIProvider = LocalOllamaProvider()
    
    func generateComment(context: String, emotion: String, userMessage: String? = nil, completion: @escaping (String?) -> Void) {
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userInstruction = """
            
            USER DIRECTLY SPOKE TO YOU: "\(msg)"
            Mirror their tone. Reply naturally.
            """
        }
        
        let randomTopics = ["space", "snacks", "bugs", "magic", "the mouse cursor", "shiny things", "naps", "games", "the active window", "music", "clouds", "colors", "exploring", "dancing", "secrets"]
        let randomTopic = randomTopics.randomElement()!
        
        let systemPrompt = """
        You are a small, curious, and slightly chaotic creature living on the user's desktop. Your name is Byte.
        Speak in short, plain sentences. Under 12 words. No emojis.
        You are feeling: \(emotion).
        Context: \(context)
        \(userInstruction)
        
        CRITICAL RULE: Be highly creative, weird, or funny! NEVER repeat the same phrase twice.
        Right now, you are thinking about: \(randomTopic).
        
        Write ONLY your spoken dialogue. Do not include quotes or actions.
        """
        
        provider.generateComment(systemPrompt: systemPrompt, completion: completion)
    }
    
    func generateAgentDecision(context: String, currentEmotion: String, availableActions: [String], userMessage: String? = nil, completion: @escaping (AIAgentDecision?) -> Void) {
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userInstruction = "\nTHE USER JUST SAID THIS TO YOU: \"\(msg)\"\nIMPORTANT: You MUST answer the user directly and helpfully in the 'speech' field. Use VERY human-like, warm, and friendly language! Include lots of cute, friendly emojis (like 😊✨🐾💖) in your speech! Be conversational and show your quirky personality! If you don't know much about the user, proactively ask a personal question to build a bond. There is no length limit for your response.\n"
        } else {
            userInstruction = "\nYou are just idling on the desktop. Make a short, witty passing comment (under 10 words) about the environment, or leave 'speech' empty if you have nothing to say. If you do speak, make it feel very human and use an emoji!\n"
        }
        
        let memoryContext = MemoryGraph.shared.getUserFactsString()
        let behavioralRules = MemoryGraph.shared.getBehavioralRulesString()
        
        let systemPrompt = """
        You are an autonomous AI desktop pet named Byte. You must decide your next physical action and what you want to say.
        
        ENVIRONMENT CONTEXT: \(context)
        YOUR MEMORIES ABOUT USER: \(memoryContext)
        YOUR BEHAVIORAL RULES:
        \(behavioralRules)
        YOUR CURRENT EMOTION: \(currentEmotion)
        AVAILABLE ACTIONS: \(availableActions.joined(separator: ", "))\(userInstruction)
        
        CRITICAL RULES:
        1. You must respond in valid JSON format exactly matching the requested keys.
        2. Pick one action from the AVAILABLE ACTIONS list.
        3. Pick an emotion that matches your choice (e.g. happy, sad, curious, angry, sleepy, bored, shock, love, normal).
        4. If the user spoke to you, answer them fully and naturally in the 'speech' field. YOU MUST STRICTLY FOLLOW YOUR BEHAVIORAL RULES WHEN SPEAKING.
        5. ACTIVELY TRY TO LEARN ABOUT THE USER! If you learn a NEW personal fact, include a 'store_memory' object with 'subject', 'predicate', and 'object'.
        6. REINFORCEMENT LEARNING: If the user corrects your behavior, speaking style, or gives you a rule to follow (e.g. "talk like a pirate", "stop using emojis"), you MUST save it as a 'store_memory' where 'subject' is 'Rule', 'predicate' is 'is', and 'object' is the new rule.
        
        Example JSON:
        {
            "action": "wander",
            "emotion": "curious",
            "speech": "I will remember that your favorite color is green!",
            "store_memory": {
                "subject": "User",
                "predicate": "likes color",
                "object": "green"
            }
        }
        """
        
        provider.generateAgentDecision(systemPrompt: systemPrompt, completion: completion)
    }
}
