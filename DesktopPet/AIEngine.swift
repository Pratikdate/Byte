import Foundation

struct AIAgentDecision: Codable {
    let action: String
    let emotion: String
    let speech: String
    let store_memory: MemoryFact?
    let target_x: Double?
    let target_y: Double?
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

// MARK: - Local Ollama Provider (Streaming)
class LocalOllamaProvider: NSObject, AIProvider, URLSessionDataDelegate {
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
        // Fallback for non-streaming usage
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
                   
                   // Try to parse [ACTION: xxx] [EMOTION: xxx] from the response instead of JSON
                   var action = "idle"
                   var emotion = "normal"
                   var speech = responseText
                   
                   if let actionRange = speech.range(of: "[ACTION: ") {
                       let sub = speech[actionRange.upperBound...]
                       if let endRange = sub.range(of: "]") {
                           action = String(sub[..<endRange.lowerBound])
                       }
                   }
                   if let emotionRange = speech.range(of: "[EMOTION: ") {
                       let sub = speech[emotionRange.upperBound...]
                       if let endRange = sub.range(of: "]") {
                           emotion = String(sub[..<endRange.lowerBound])
                       }
                   }
                   
                   // Clean up the tags from speech
                   speech = speech.replacingOccurrences(of: "\\[ACTION:.*?\\]", with: "", options: .regularExpression)
                   speech = speech.replacingOccurrences(of: "\\[EMOTION:.*?\\]", with: "", options: .regularExpression)
                   speech = speech.trimmingCharacters(in: .whitespacesAndNewlines)

                   let decision = AIAgentDecision(action: action, emotion: emotion, speech: speech, store_memory: nil, target_x: nil, target_y: nil)
                   completion(decision)
                }
            } catch {
                print("Failed to decode Ollama response: \(error)")
            }
            completion(nil)
        }
        task.resume()
    }
    
    // --- STREAMING SUPPORT ---
    private var onActionCallback: ((AIAgentDecision) -> Void)?
    private var onSentenceCallback: ((String) -> Void)?
    private var onCompleteCallback: (() -> Void)?
    
    private var buffer = ""
    private var actionParsed = false
    private var parsedAction = "idle"
    private var parsedEmotion = "normal"
    private var currentTask: URLSessionDataTask?
    
    func generateAgentDecisionStreaming(systemPrompt: String, onAction: @escaping (AIAgentDecision) -> Void, onSentence: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        
        self.onActionCallback = onAction
        self.onSentenceCallback = onSentence
        self.onCompleteCallback = onComplete
        
        self.buffer = ""
        self.actionParsed = false
        self.parsedAction = "idle"
        self.parsedEmotion = "normal"
        
        currentTask?.cancel()
        
        guard let url = URL(string: endpoint) else { return }
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": systemPrompt,
            "stream": true // Enable streaming
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        currentTask = session.dataTask(with: request)
        currentTask?.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        let lines = string.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseToken = json["response"] as? String {
                
                buffer += responseToken
                
                // 1. Parse [ACTION: xxx] and [EMOTION: xxx] before sending speech
                if !actionParsed {
                    let upperBuffer = buffer.uppercased()
                    let hasAction = upperBuffer.contains("ACTION")
                    let hasEmotion = upperBuffer.contains("EMOTION")
                    
                    // Wait until we have both tags, or we've received enough characters to give up waiting
                    if (hasAction && hasEmotion && buffer.contains("]")) || buffer.count > 80 || buffer.contains("\n") {
                    
                    if let actionMatch = upperBuffer.range(of: "ACTION") {
                        let sub = buffer[actionMatch.upperBound...]
                        if let end = sub.range(of: "]") {
                            let raw = String(sub[..<end.lowerBound])
                            parsedAction = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                        }
                    }
                    
                    if let emotionMatch = upperBuffer.range(of: "EMOTION") {
                        let sub = buffer[emotionMatch.upperBound...]
                        if let end = sub.range(of: "]") {
                            let raw = String(sub[..<end.lowerBound])
                            parsedEmotion = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                        }
                    }
                    
                    let decision = AIAgentDecision(action: parsedAction, emotion: parsedEmotion, speech: "", store_memory: nil, target_x: nil, target_y: nil)
                    
                    DispatchQueue.main.async {
                        self.onActionCallback?(decision)
                    }
                    
                    actionParsed = true
                    // Clear all tags from the buffer by stripping everything up to the last ]
                    if let lastBracket = buffer.range(of: "]", options: .backwards) {
                        buffer = String(buffer[lastBracket.upperBound...]).trimmingCharacters(in: .whitespaces)
                    }
                }
                }
                
                // 2. Chunk sentences once action is parsed
                if actionParsed {
                    let terminators = [". ", "! ", "? ", "\n", ".\n", "!\n", "?\n", ", ", "... "]
                    for term in terminators {
                        if let range = buffer.range(of: term) {
                            let sentence = String(buffer[..<range.lowerBound]) + term.trimmingCharacters(in: .whitespaces)
                            
                            // Strip any lingering tags (e.g. [EMOTION: happy]) from the sentence
                            var finalSentence = sentence.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                            finalSentence = finalSentence.trimmingCharacters(in: .whitespaces)
                            
                            if !finalSentence.isEmpty {
                                DispatchQueue.main.async {
                                    self.onSentenceCallback?(finalSentence)
                                }
                            }
                            buffer = String(buffer[range.upperBound...])
                            break
                        }
                    }
                }
                
                if let done = json["done"] as? Bool, done {
                    var remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    remainder = remainder.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                    
                    if !remainder.isEmpty && actionParsed {
                        DispatchQueue.main.async {
                            self.onSentenceCallback?(remainder)
                        }
                    }
                    DispatchQueue.main.async {
                        self.onCompleteCallback?()
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code == NSURLErrorCancelled {
            return
        }
        DispatchQueue.main.async {
            self.onCompleteCallback?()
        }
    }
    
    func cancelStreaming() {
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - Local 2B LLM Provider (faster-inference)
/// Uses local 2B model via faster-inference server for fast, natural dialogue
class Local2BLLMProvider: AIProvider {
    private let endpoint = "http://localhost:8080/generate"  // fast-inference server
    private let modelName = "phi-2" // or distilbert-base, adjust per your model

    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "prompt": systemPrompt,
            "max_length": 50,
            "temperature": 0.8,
            "top_p": 0.9
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0

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
                   let generatedText = json["generated_text"] as? String {
                    let cleaned = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            "prompt": systemPrompt,
            "max_length": 300,
            "temperature": 0.7,
            "top_p": 0.95
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0

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
                   let generatedText = json["generated_text"] as? String {

                    var cleanText = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                print("Failed to decode 2B LLM JSON decision: \(error)")
            }
            completion(nil)
        }
        task.resume()
    }
}

// MARK: - AI Engine
class AIEngine {
    static let shared = AIEngine()

    // Use Ollama + Gemma 2B by default for fast, natural dialogue on-device
    var provider: AIProvider = LocalOllamaProvider()

    private let dialogueHistory = NSMutableArray()
    private let maxHistorySize = 20

    func generateComment(context: String, emotion: String, userMessage: String? = nil, completion: @escaping (String?) -> Void) {

        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userInstruction = """

            USER DIRECTLY SPOKE TO YOU: "\(msg)"
            Mirror their tone. Reply naturally and conversationally.
            """
        }

        let randomTopics = ["space", "snacks", "bugs", "magic", "the mouse cursor", "shiny things", "naps", "games", "the active window", "music", "clouds", "colors", "exploring", "dancing", "secrets"]
        let randomTopic = randomTopics.randomElement()!

        // Add emotional tone hints for more natural speech
        let emotionalTone = emotionalInstructions(for: emotion)

        let systemPrompt = """
        You are Byte, a small, curious desktop creature. Speak naturally like a real being—conversational, sometimes silly, sometimes thoughtful.
        Keep it short: under 12 words. No emojis. One thought per line.
        Current feeling: \(emotion). \(emotionalTone)
        Context: \(context)
        \(userInstruction)

        CRITICAL: Be creative, weird, or funny. Never repeat phrases from your last 10 lines.
        Right now thinking about: \(randomTopic).

        Write ONLY dialogue. No quotes, no actions, no asterisks.
        """

        provider.generateComment(systemPrompt: systemPrompt) { response in
            if let response = response {
                // Enhance with natural pauses & rhythm before playback
                let enhanced = DialogueNaturalness.enhanceForSpeech(response, emotion: emotion)

                self.dialogueHistory.add(enhanced)
                if self.dialogueHistory.count > self.maxHistorySize {
                    self.dialogueHistory.removeObject(at: 0)
                }

                // Thread it so gap-timing + anti-repetition apply to these lines too.
                InteractionDirector.shared.noteSpoke(enhanced)
                completion(enhanced)
            } else {
                completion(nil)
            }
        }
    }

    private func emotionalInstructions(for emotion: String) -> String {
        switch emotion.lowercased() {
        case "happy", "excited":
            return "Speak with energy! Use quick words, bouncy rhythm."
        case "sad", "lonely":
            return "Soft, slower pace. A bit wistful."
        case "curious":
            return "Inquisitive, questioning. Use 'what if' or 'wonder'."
        case "annoyed", "angry":
            return "Short, clipped words. A bit snippy."
        case "sleepy", "bored":
            return "Slow... words... maybe... drift... off..."
        default:
            return "Calm and steady."
        }
    }
    
    func generateAgentDecision(context: String, currentEmotion: String, availableActions: [String], userMessage: String? = nil, completion: @escaping (AIAgentDecision?) -> Void) {
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userInstruction = "\nTHE USER JUST SAID THIS TO YOU: \"\(msg)\"\nIMPORTANT: You MUST answer the user directly and helpfully in the 'speech' field. Use VERY human-like, warm, and friendly language! Be conversational and show your quirky personality! If you don't know much about the user, proactively ask a personal question to build a bond. There is no length limit for your response. (Do NOT use emojis, because your response will be spoken aloud by a voice synthesizer, but make your words expressive!)\n\nSPATIAL COMMANDS: If the user tells you to go somewhere or do a spatial action, pick the matching action:\n- \"go sit in the corner\" / \"sit in corner\" → action: \"sitOnCorner\"\n- \"sit on the menu bar\" / \"go to the top\" → action: \"sitOnMenuBar\"\n- \"climb that window\" / \"climb up\" / \"sit on the window\" → action: \"climbWindow\"\n- \"push that window\" / \"push it\" → action: \"pushWidget\"\n- \"tap on the window\" / \"knock\" → action: \"tapWindow\"\n- \"come here\" / \"come to me\" → action: \"wander\" (you will walk toward cursor)\n- \"go away\" / \"leave me alone\" → action: \"sitOnCorner\" (walk to farthest corner)\n- \"do a backflip\" / \"flip\" → action: \"backflip\"\n- \"dance\" / \"headbang\" → action: \"headbang\" or \"dance\"\n- \"wave\" / \"say hi\" → action: \"wave\"\n- \"go to sleep\" → action: \"sleep\"\n- \"wake up\" → action: \"jump\"\n"
        } else {
            userInstruction = "\nYou are just idling on the desktop. Make a short, witty passing comment (under 10 words) about the environment, or leave 'speech' empty if you have nothing to say. If you do speak, make it feel very human and expressive (no emojis)!\n"
        }

        let memoryContext = MemoryGraph.shared.getUserFactsString()
        let behavioralRules = MemoryGraph.shared.getBehavioralRulesString()

        let emotionalTone = emotionalInstructions(for: currentEmotion)

        // Conversation memory + attention — the anti-repetition and tone steering.
        let conversation = InteractionDirector.shared.conversationContext()
        let attentionNote = InteractionDirector.shared.attentionDirective()
        let avoidOpeners = InteractionDirector.shared.recentOpeners()
        let avoidLine = avoidOpeners.isEmpty
            ? ""
            : "DO NOT begin your reply with any of these recently-used openers: \(avoidOpeners.map { "\"\($0)\"" }.joined(separator: ", ")). Say something fresh.\n"

        let systemPrompt = """
        You are an autonomous AI desktop pet named Byte. You must decide your next physical action and what you want to say.

        ENVIRONMENT CONTEXT: \(context)
        USER ATTENTION: \(attentionNote)
        \(conversation)
        YOUR MEMORIES ABOUT USER: \(memoryContext)
        YOUR BEHAVIORAL RULES:
        \(behavioralRules)
        YOUR CURRENT EMOTION: \(currentEmotion). \(emotionalTone)
        \(avoidLine)AVAILABLE ACTIONS: \(availableActions.joined(separator: ", "))\(userInstruction)

        ACTION DESCRIPTIONS:
        - idle: Stand still, breathe
        - wander: Walk to a random spot on the desktop
        - sleep: Walk to a corner and fall asleep
        - jump: Happy jump
        - sit: Sit down with legs splayed
        - spin: Spin around once
        - dance: Dance with jumps and spins
        - stretch: Stretch tall then shrink back
        - roll: Roll sideways
        - sitOnCorner: Walk to the nearest screen corner and sit with legs dangling
        - sitOnMenuBar: Walk up to the top menu bar and perch there
        - climbWindow: Climb up and sit on top of the nearest window
        - pushWidget: Walk to a window edge and push against it
        - tapWindow: Walk to a window and tap/bonk head on it
        - sneeze: Do an explosive sneeze animation
        - backflip: Do a celebratory backflip
        - headbang: Rock head rhythmically like jamming to music
        - wave: Wave hello using ear headphones

        CRITICAL RULES:
        1. You must respond by starting with the tags [ACTION: xxx] and [EMOTION: xxx].
        2. Pick one action from the AVAILABLE ACTIONS list.
        3. Pick an emotion that matches your choice (e.g. happy, sad, curious, angry, sleepy, bored, shock, love, normal, proud, excited, embarrassed).
        4. If the user spoke to you, answer them fully and naturally directly after the tags. YOU MUST STRICTLY FOLLOW YOUR BEHAVIORAL RULES WHEN SPEAKING.
        5. NEVER repeat a line or phrasing you already used in RECENT CONVERSATION. Vary your wording, sentence shape, and openers every time. If you have nothing fresh to add, just output the tags and stop.
        6. Match the USER ATTENTION note: when the user is away or focused, prefer a quiet action and no speech.
        7. When speaking, naturally include conversational filler words (e.g., "hmm...", "uhh...", "ah,") at the start to simulate natural thinking time.
        8. KEEP YOUR RESPONSE EXTREMELY SHORT. Never exceed 2 short sentences.
        9. DO NOT overuse the user's name. You should rarely say their name, unless explicitly greeting them.
        10. BE INTERESTING! Don't just walk or stand still. Frequently pick fun, expressive actions like backflip, sneeze, headbang, spin, or wave to match your dialogue!

        Example Response:
        [ACTION: sitOnCorner] [EMOTION: happy] On my way!
        """

        provider.generateAgentDecision(systemPrompt: systemPrompt) { decision in
            // Apply naturalness to speech field if present
            if let decision = decision, !decision.speech.isEmpty {
                let enhanced = DialogueNaturalness.enhanceForSpeech(decision.speech, emotion: currentEmotion)
                // Create new decision with enhanced speech
                let enhancedDecision = AIAgentDecision(
                    action: decision.action,
                    emotion: decision.emotion,
                    speech: enhanced,
                    store_memory: decision.store_memory,
                    target_x: decision.target_x,
                    target_y: decision.target_y
                )
                completion(enhancedDecision)
            } else {
                completion(decision)
            }
        }
    }
    
    func generateAgentDecisionStreaming(context: String, currentEmotion: String, availableActions: [String], userMessage: String? = nil, onAction: @escaping (AIAgentDecision) -> Void, onSentence: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userInstruction = "\nTHE USER JUST SAID THIS TO YOU: \"\(msg)\"\nIMPORTANT: You MUST answer the user directly and helpfully. Use VERY human-like, warm, and friendly language! Be conversational and show your quirky personality! If you don't know much about the user, proactively ask a personal question to build a bond. Keep your response SHORT, under 3 sentences. (Do NOT use emojis, because your response will be spoken aloud by a voice synthesizer, but make your words expressive!)\n"
        } else {
            userInstruction = "\nYou are just idling on the desktop. Make a short, witty passing comment (under 10 words) about the environment, or leave 'speech' empty if you have nothing to say. If you do speak, make it feel very human and expressive (no emojis)!\n"
        }

        let memoryContext = MemoryGraph.shared.getUserFactsString()
        let behavioralRules = MemoryGraph.shared.getBehavioralRulesString()
        let emotionalTone = emotionalInstructions(for: currentEmotion)
        let conversation = InteractionDirector.shared.conversationContext()
        let attentionNote = InteractionDirector.shared.attentionDirective()
        let avoidOpeners = InteractionDirector.shared.recentOpeners()
        let avoidLine = avoidOpeners.isEmpty
            ? ""
            : "DO NOT begin your reply with any of these recently-used openers: \(avoidOpeners.map { "\"\($0)\"" }.joined(separator: ", ")). Say something fresh.\n"

        let systemPrompt = """
        You are an autonomous AI desktop pet named Byte. You must decide your next physical action and what you want to say.

        ENVIRONMENT CONTEXT: \(context)
        USER ATTENTION: \(attentionNote)
        \(conversation)
        YOUR MEMORIES ABOUT USER: \(memoryContext)
        YOUR BEHAVIORAL RULES:
        \(behavioralRules)
        YOUR CURRENT EMOTION: \(currentEmotion). \(emotionalTone)
        \(avoidLine)AVAILABLE ACTIONS: \(availableActions.joined(separator: ", "))\(userInstruction)

        ACTION DESCRIPTIONS:
        - idle, wander, sleep, jump, sit, spin, dance, stretch, roll, sitOnCorner, sitOnMenuBar, climbWindow, pushWidget, tapWindow, sneeze, backflip, headbang, wave

        CRITICAL RULES:
        1. You must respond by starting with the tags [ACTION: xxx] and [EMOTION: xxx].
        2. Pick one action from the AVAILABLE ACTIONS list.
        3. Pick an emotion that matches your choice (happy, sad, curious, angry, sleepy, bored, shock, love, normal, proud, excited, embarrassed).
        4. Answer the user directly after the tags. NEVER use emojis.
        5. When speaking, naturally include conversational filler words (e.g., "hmm...", "uhh...", "ah,") at the start to simulate natural thinking time.
        6. KEEP YOUR RESPONSE EXTREMELY SHORT. Never exceed 2 short sentences.
        7. DO NOT overuse the user's name. You should rarely say their name, unless explicitly greeting them.
        8. BE INTERESTING! Don't just walk or stand still. Frequently pick fun, expressive actions like backflip, sneeze, headbang, spin, or wave to match your dialogue!

        Example Response:
        [ACTION: sitOnCorner] [EMOTION: happy] On my way!
        """

        if let streamingProvider = provider as? LocalOllamaProvider {
            streamingProvider.generateAgentDecisionStreaming(systemPrompt: systemPrompt, onAction: onAction, onSentence: onSentence, onComplete: onComplete)
        } else {
            // Fallback for non-streaming providers
            provider.generateAgentDecision(systemPrompt: systemPrompt) { decision in
                if let d = decision {
                    onAction(d)
                    if !d.speech.isEmpty {
                        onSentence(d.speech)
                    }
                    onComplete()
                } else {
                    onComplete()
                }
            }
        }
    }
    
    func cancelCurrentGeneration() {
        if let streamingProvider = provider as? LocalOllamaProvider {
            streamingProvider.cancelStreaming()
        }
    }
}
