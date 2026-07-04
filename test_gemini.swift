import Foundation

struct AIPetDecision: Codable {
    let emotion: String
    let action: String
    let thought: String
}

let apiKey = "AQ.Ab8RN6JquuZTkTTYuwK4u8G1zZeUG6NXcKmWbqVohVFvSbyawA"
let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"

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
Visible Windows: Xcode. Taskbar/Dock is visible. Current Energy: 90. Current Emotion: normal.
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

guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
    print("Invalid URL")
    exit(1)
}

var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try! JSONSerialization.data(withJSONObject: payload, options: [])

let group = DispatchGroup()
group.enter()

let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { group.leave() }
    guard let data = data, error == nil else {
        print("Network Error: \(error?.localizedDescription ?? "Unknown")")
        return
    }
    
    if let httpResponse = response as? HTTPURLResponse {
        print("HTTP Status Code: \(httpResponse.statusCode)")
    }
    
    let str = String(data: data, encoding: .utf8)
    print("Raw Response: \(str ?? "")")
    
    do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first,
           let responseString = firstPart["text"] as? String,
           let responseData = responseString.data(using: .utf8) {
            
            let decision = try JSONDecoder().decode(AIPetDecision.self, from: responseData)
            print("Successfully parsed decision: \(decision)")
        } else {
            print("Failed to traverse JSON hierarchy.")
        }
    } catch {
        print("Parse Error: \(error)")
    }
}
task.resume()
group.wait()
