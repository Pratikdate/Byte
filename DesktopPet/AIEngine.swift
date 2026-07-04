import Foundation

struct AIPetDecision: Codable {
    let emotion: String
    let action: String
    let thought: String
}

class AIEngine {
    static let shared = AIEngine()
    
    // Gemini API Configuration
    private let apiKey = "AIzaSyB3a979Ex_luKKD6xiNPJjad18p9Dt-zjE"
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"
    
    func decideNextMove(context: String, completion: @escaping (AIPetDecision?) -> Void) {
        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
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
            "contents": [
                [
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
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
                // Parse Gemini's nested response format
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let responseString = firstPart["text"] as? String,
                   let responseData = responseString.data(using: .utf8) {
                    
                    print("🤖 Gemini AI Response: \(responseString)")
                    
                    let decision = try JSONDecoder().decode(AIPetDecision.self, from: responseData)
                    completion(decision)
                } else {
                    print("AIEngine Error: Unexpected JSON format from Gemini")
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
