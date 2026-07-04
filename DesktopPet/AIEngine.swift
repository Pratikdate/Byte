import Foundation

struct AIPetDecision: Codable {
    let emotion: String
    let action: String
    let thought: String
}

class AIEngine {
    static let shared = AIEngine()
    
    // We default to a local Ollama server running Llama 3 or Phi 3
    // You can install Ollama from ollama.com and run `ollama run llama3` in terminal
    private let endpoint = "http://localhost:11434/api/generate"
    private let model = "llama3" // or "phi3" or "mistral"
    
    func decideNextMove(context: String, completion: @escaping (AIPetDecision?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        
        let systemPrompt = """
        You are a cute, slightly mischievous AI desktop pet living on a macOS screen.
        You can see what the user is doing. Your goal is to decide your next move based on your environment.
        Respond ONLY in valid JSON format matching this structure, with no markdown, no backticks, and no extra text:
        {
            "emotion": "happy|sad|sleepy|excited|curious|bored|thinking",
            "action": "wander|peekWindow|sitOnTaskbar|idle|sleep|jump|spin",
            "thought": "A short, cute internal thought about what you see or feel (max 10 words)"
        }
        
        Current Environment:
        \(context)
        """
        
        let payload: [String: Any] = [
            "model": model,
            "prompt": systemPrompt,
            "format": "json",
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
                print("AIEngine Error: \(error?.localizedDescription ?? "Unknown")")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseString = json["response"] as? String,
                   let responseData = responseString.data(using: .utf8) {
                    
                    let decision = try JSONDecoder().decode(AIPetDecision.self, from: responseData)
                    completion(decision)
                } else {
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
