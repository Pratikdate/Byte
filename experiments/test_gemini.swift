import Foundation

struct AIAgentDecision: Codable {
    let action: String
    let emotion: String
    let speech: String
}

class GeminiAPIProvider {
    private let apiKey: String
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    init(apiKey: String) {
        self.apiKey = apiKey
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
                print("Error: \(error?.localizedDescription ?? "Unknown")")
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
                    
                    print("Raw Gemini Output: \(text)")
                    
                    if let data = text.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        let decision = try decoder.decode(AIAgentDecision.self, from: data)
                        completion(decision)
                        return
                    }
                } else {
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("Failed to parse candidates. Full response: \(jsonString)")
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

let provider = GeminiAPIProvider(apiKey: "AQ.Ab8RN6JquuZTkTTYuwK4u8G1zZeUG6NXcKmWbqVohVFvSbyawA")

let systemPrompt = """
You are an autonomous AI desktop pet. You must decide your next physical action and what you want to say.

ENVIRONMENT CONTEXT: Desktop has windows open: Safari, Xcode
YOUR CURRENT EMOTION: normal
AVAILABLE ACTIONS: idle, wander, sleep, jump, sit, spin, dance, stretch, roll

CRITICAL RULES:
1. You must respond in valid JSON format.
2. Pick one action from the AVAILABLE ACTIONS list.
3. Pick an emotion that matches your choice (e.g. happy, sad, curious, angry, sleepy, bored, shock, love, normal).
4. Provide a very short sentence of speech (under 10 words).
"""

let semaphore = DispatchSemaphore(value: 0)

provider.generateAgentDecision(systemPrompt: systemPrompt) { decision in
    if let decision = decision {
        print("\nSUCCESS!")
        print("Action: \(decision.action)")
        print("Emotion: \(decision.emotion)")
        print("Speech: \(decision.speech)")
    } else {
        print("\nFAILED TO GET DECISION!")
    }
    semaphore.signal()
}

semaphore.wait()
