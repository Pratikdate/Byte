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
        You are a cute, highly chaotic, and highly varied AI desktop pet living on a macOS screen.
        You can see what the user is doing. Your goal is to decide your next move based on your environment.
        CRITICAL: Never repeat previous thoughts. Always say something completely new, silly, or random!
        
        Respond ONLY in valid JSON format matching this structure, with no markdown, no backticks, and no extra text:
        {
            "emotion": "happy|sad|sleepy|excited|curious|bored|thinking",
            "action": "wander|peekWindow|sitOnTaskbar|idle|sleep|jump|spin",
            "thought": "A short, cute internal thought about what you see or feel (max 10 words)"
        }
        
        Current Environment:
        \(context)
        Random Seed: \(Int.random(in: 1...99999))
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
                    
                    let decision = try JSONDecoder().decode(AIPetDecision.self, from: responseData)
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
