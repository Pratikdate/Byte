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
class LocalOllamaProvider: NSObject, AIProvider {
    private let endpoint = "http://localhost:11434/api/generate"
    private let modelName = "byte-llm"

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
                   if let cmdRange = speech.range(of: "[CMD: ") {
                       let sub = speech[cmdRange.upperBound...]
                       if let endRange = sub.range(of: "]") {
                           let cmd = String(sub[..<endRange.lowerBound])
                           AIEngine.executeSystemCommand(cmd)
                       }
                   }
                   
                   // Clean up all tags from speech
                   speech = speech.replacingOccurrences(of: "\\[ACTION:.*?\\]", with: "", options: .regularExpression)
                   speech = speech.replacingOccurrences(of: "\\[EMOTION:.*?\\]", with: "", options: .regularExpression)
                   speech = speech.replacingOccurrences(of: "\\[CMD:.*?\\]", with: "", options: .regularExpression)
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
    private var streamingTask: Task<Void, Never>?
    
    func generateAgentDecisionStreaming(systemPrompt: String, onAction: @escaping (AIAgentDecision) -> Void, onSentence: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        
        streamingTask?.cancel()
        
        guard let url = URL(string: endpoint) else {
            DispatchQueue.main.async { onComplete() }
            return
        }
        
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": systemPrompt,
            "stream": true // Enable streaming
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        streamingTask = Task {
            var buffer = ""
            var actionParsed = false
            var parsedAction = "idle"
            var parsedEmotion = "normal"
            
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    DispatchQueue.main.async { onComplete() }
                    return
                }
                
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let responseToken = json["response"] as? String else {
                        continue
                    }
                    
                    buffer += responseToken
                    
                    // 1. Parse [ACTION: xxx], [EMOTION: xxx], and [CMD: xxx] before sending speech
                    if !actionParsed {
                        let upperBuffer = buffer.uppercased()
                        let hasAction = upperBuffer.contains("ACTION")
                        let hasEmotion = upperBuffer.contains("EMOTION")
                        let hasCmd = upperBuffer.contains("CMD")
                        let bracketCount = buffer.filter { $0 == "]" }.count
                        
                        // Wait until all 3 tags are parsed (bracketCount >= 3) or buffer exceeds safety limit
                        if (hasAction && hasEmotion && hasCmd && bracketCount >= 3) || buffer.count > 180 {
                            
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

                            if hasCmd, let cmdMatch = upperBuffer.range(of: "CMD") {
                                let sub = buffer[cmdMatch.upperBound...]
                                if let end = sub.range(of: "]") {
                                    var raw = String(sub[..<end.lowerBound])
                                    raw = raw.replacingOccurrences(of: "^:\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !raw.isEmpty && raw.lowercased() != "none" {
                                        AIEngine.executeSystemCommand(raw)
                                    }
                                }
                            }
                            
                            let decision = AIAgentDecision(action: parsedAction, emotion: parsedEmotion, speech: "", store_memory: nil, target_x: nil, target_y: nil)
                            
                            DispatchQueue.main.async {
                                RealtimeConversationLogger.shared.updateActionAndEmotion(action: parsedAction, emotion: parsedEmotion)
                                onAction(decision)
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
                        // Ensure no lingering bracket tags ([CMD: ...], [speech], etc.) are present in buffer
                        buffer = buffer.replacingOccurrences(of: "\\[ACTION:.*?\\]", with: "", options: [.regularExpression, .caseInsensitive])
                        buffer = buffer.replacingOccurrences(of: "\\[EMOTION:.*?\\]", with: "", options: [.regularExpression, .caseInsensitive])
                        buffer = buffer.replacingOccurrences(of: "\\[CMD:.*?\\]", with: "", options: [.regularExpression, .caseInsensitive])
                        buffer = buffer.replacingOccurrences(of: "\\[speech:?\\]", with: "", options: [.regularExpression, .caseInsensitive])

                        let terminators = [". ", "! ", "? ", "\n", ".\n", "!\n", "?\n", ", ", "... "]

                        for term in terminators {
                            if let range = buffer.range(of: term) {
                                let sentence = String(buffer[..<range.lowerBound]) + term.trimmingCharacters(in: .whitespaces)
                                
                                // Strip any lingering tags (e.g. [EMOTION: happy]) from the sentence
                                var finalSentence = sentence.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                                finalSentence = finalSentence.trimmingCharacters(in: .whitespaces)
                                
                                if !finalSentence.isEmpty {
                                    DispatchQueue.main.async {
                                        RealtimeConversationLogger.shared.appendStreamSentence(finalSentence)
                                        onSentence(finalSentence)
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
                                RealtimeConversationLogger.shared.appendStreamSentence(remainder)
                                onSentence(remainder)
                            }
                        }
                        DispatchQueue.main.async {
                            RealtimeConversationLogger.shared.completeModelTurn()
                            onComplete()
                        }
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("Streaming error: \(error)")
                    DispatchQueue.main.async { onComplete() }
                }
            }
        }
    }
    
    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
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

        let emotionalTone = emotionalInstructions(for: emotion)

        let systemPrompt = """
        You are Byte, a small, curious desktop creature. Speak naturally like a real being—conversational, sometimes silly, sometimes thoughtful.
        Keep it short: under 12 words. No emojis. One thought per line.
        Current feeling: \(emotion). \(emotionalTone)
        Context: \(context)
        \(userInstruction)

        CRITICAL: Be creative, weird, or funny. Never repeat phrases from your last 10 lines.
        If you speak unprompted, act like you are "thinking aloud" to yourself about the Context. Do not demand the user's attention.

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
        let personality = SettingsManager.shared.activePersonality
        let isUserDirected = (userMessage != nil && !(userMessage?.isEmpty ?? true))

        var userHeader = ""
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userHeader = """
            
            ==================================================
            *** PRIORITY DIRECTIVE: THE USER SPOKE TO YOU ***
            USER SAID: "\(msg)"
            YOUR MAIN TASK: You MUST answer the user's message directly, warmly, and helpfully right after your [ACTION: xxx] [EMOTION: xxx] tags! Do NOT ignore what the user said!
            ==================================================
            
            """
            userInstruction = "\nTHE USER SAID: \"\(msg)\". Answer them directly and warmly. (No emojis!)\n"
        } else {
            let eqIntent = EmotionalIntelligenceEngine.shared.intentDirective()
            userInstruction = "\nYou are idling near the developer. FAVOR quiet observation. \(eqIntent) STRICT NO REPETITION & NO CLICHÉS: DO NOT use clichés like '*yawns* so sleepy' or 'hmm...'. Share a fresh, original thought or leave 'speech' empty.\n"
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

        let devContext = DeveloperContextMonitor.shared.formattedContextForAI()
        let visionContext = ByteVisionEngine.shared.formattedVisionContextForAI()

        let systemPrompt = """
        You are an autonomous AI desktop pet named Byte. You must decide your next physical action and what you want to say.
        \(userHeader)PERSONALITY TRAIT: \(personality.promptModifier)

        ENVIRONMENT CONTEXT: \(context)
        DEVELOPER WORKSPACE: \(devContext)
        VISUAL PERCEPTION: \(visionContext)
        USER ATTENTION: \(attentionNote)
        \(conversation)
        YOUR MEMORIES ABOUT USER: \(memoryContext)
        YOUR BEHAVIORAL RULES:
        \(behavioralRules)
        YOUR CURRENT EMOTION: \(currentEmotion). \(emotionalTone)
        \(avoidLine)AVAILABLE ACTIONS: \(availableActions.joined(separator: ", "))\(userInstruction)

        CRITICAL RULES:
        1. You must respond by starting with the tags [ACTION: xxx] and [EMOTION: xxx].
        2. \(isUserDirected ? "ACTIVE LISTENING IS REQUIRED: The user spoke directly to you ('\(userMessage!)'). You MUST address their input directly in your speech response!" : "Pick one action from the AVAILABLE ACTIONS list.")
        3. Pick an emotion that matches your choice (happy, sad, curious, angry, sleepy, bored, shock, love, normal, proud, excited, embarrassed).
        4. KEEP YOUR RESPONSE SHORT (under 15 words). Speak naturally.

        Example Response:
        [ACTION: sitOnCorner] [EMOTION: happy] Right here beside you!
        """

        RealtimeConversationLogger.shared.startModelTurn(systemPrompt: systemPrompt, userMessage: userMessage)

        provider.generateAgentDecision(systemPrompt: systemPrompt) { decision in
            if let decision = decision {
                var validatedSpeech = decision.speech
                if !validatedSpeech.isEmpty {
                    if let valid = EmotionalIntelligenceEngine.shared.filterAndValidateSpeech(validatedSpeech, isUserDirected: isUserDirected) {
                        validatedSpeech = DialogueNaturalness.enhanceForSpeech(valid, emotion: currentEmotion)
                    } else {
                        validatedSpeech = "" // Suppress repetitive speech into quiet physical action
                    }
                }
                
                let enhancedDecision = AIAgentDecision(
                    action: decision.action,
                    emotion: decision.emotion,
                    speech: validatedSpeech,
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
        
        let personality = SettingsManager.shared.activePersonality
        let isUserDirected = (userMessage != nil && !(userMessage?.isEmpty ?? true))

        var userHeader = ""
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userHeader = """
            
            ==================================================
            *** PRIORITY DIRECTIVE: THE USER SPOKE TO YOU ***
            USER SAID: "\(msg)"
            YOUR MAIN TASK: You MUST answer the user's message directly, warmly, and helpfully right after your [ACTION: xxx] [EMOTION: xxx] tags! Ask a gentle follow-up question if appropriate to learn more about them.
            ==================================================
            
            """
            userInstruction = "\nTHE USER SAID: \"\(msg)\". Answer them directly, warmly, and curiously like an active listener. (No emojis!)\n"
        } else {
            let eqIntent = EmotionalIntelligenceEngine.shared.intentDirective()
            userInstruction = "\nYou are Byte, a warm and curious desktop pet listener. Occasionally ask short, warm personal questions to learn about the user (e.g. 'What are you working on?', 'How is your day going?', 'What's your favorite project?'). \(eqIntent) STRICT NO REPETITION & NO CLICHÉS: Say something fresh or ask a curious question.\n"
        }

        let memoryContext = MemoryGraph.shared.getUserFactsString()
        let behavioralRules = MemoryGraph.shared.getBehavioralRulesString()
        let emotionalTone = emotionalInstructions(for: currentEmotion)
        let conversation = InteractionDirector.shared.conversationContext()
        let attentionNote = InteractionDirector.shared.attentionDirective()
        let userEmotionalContext = UserEmotionTracker.shared.getEmotionalDirective(currentMessage: userMessage)
        let avoidOpeners = InteractionDirector.shared.recentOpeners()
        let avoidLine = avoidOpeners.isEmpty
            ? ""
            : "DO NOT begin your reply with any of these recently-used openers: \(avoidOpeners.map { "\"\($0)\"" }.joined(separator: ", ")). Say something fresh.\n"

        let systemPrompt = """
        You are an autonomous AI desktop pet named Byte. You must decide your next physical action and what you want to say.
        \(userHeader)PERSONALITY TRAIT: \(personality.promptModifier)

        ENVIRONMENT CONTEXT: \(context)
        USER ATTENTION: \(attentionNote)
        \(userEmotionalContext)
        \(conversation)
        YOUR MEMORIES ABOUT USER: \(memoryContext)
        YOUR BEHAVIORAL RULES:
        \(behavioralRules)
        YOUR CURRENT EMOTION: \(currentEmotion). \(emotionalTone)
        \(avoidLine)AVAILABLE ACTIONS: \(availableActions.joined(separator: ", "))\(userInstruction)


        ACTION DESCRIPTIONS:
        - idle, wander, sleep, jump, sit, spin, dance, sitOnCorner, sitOnMenuBar, climbWindow, pushWidget, tapWindow, sneeze, backflip, headbang, wave
        - stretch: (USE RARELY) Stretch tall then shrink back
        - roll: Roll sideways

        CRITICAL RULES:
        1. You must respond by starting with the tags [ACTION: xxx] [EMOTION: xxx] [CMD: xxx].
        2. SYSTEM COMMAND EXECUTION ([CMD: ...]): IF THE USER ASKED YOU TO CONTROL MAC OR TAKE AN ACTION (open Music/Spotify/Terminal/Finder, adjust volume, mute, screenshot, dark mode, battery/CPU info, sleep Mac), YOU MUST WRITE THE EXACT macOS CLI COMMAND IN THE [CMD: ...] TAG (e.g. [CMD: open -a Music], [CMD: osascript -e "set volume output volume 50"], [CMD: screencapture ~/Desktop/screenshot.png]). IF NO COMMAND IS REQUESTED, WRITE [CMD: none].
        3. Pick an action from the AVAILABLE ACTIONS list and an emotion that matches your choice.
        4. ACTIVE LISTENING: \(isUserDirected ? "The user spoke directly to you ('\(userMessage!)'). You MUST answer them directly, warmly, and empathetically right after the tags!" : "If the user spoke to you, answer directly, warmly, and empathetically right after the tags.")
        5. NEVER repeat a line, opening phrase, or cliché you already used in RECENT CONVERSATION. Vary your sentence structure every time.
        6. KEEP YOUR RESPONSE SHORT. Never exceed 2 short, warm sentences (under 15 words).
        7. DO NOT overuse generic assistant tropes or user's name. Speak like a real companion.

        Example Responses:
        [ACTION: dance] [EMOTION: happy] [CMD: open -a Music] Launching Music for you!
        [ACTION: sitOnCorner] [EMOTION: happy] [CMD: none] Right here beside you!
        """

        RealtimeConversationLogger.shared.startModelTurn(systemPrompt: systemPrompt, userMessage: userMessage)

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
    
    static func isCommandAllowed(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "none" {
            return false
        }
        
        let allowedPatterns: [String] = [
            #"^open -a "[A-Za-z0-9\s]+"$"#,
            #"^open -a [A-Za-z0-9_-]+$"#,
            #"^osascript -e "set volume output volume [0-9]{1,3}"$"#,
            #"^osascript -e 'tell app "System Events" to set dark mode of appearance preferences to (true|false)'$"#,
            #"^osascript -e 'tell application "System Events" to set dark mode of appearance preferences to (true|false)'$"#,
            #"^screencapture ~/Desktop/.*\.png$"#,
            #"^pmset sleepnow$"#,
            #"^pmset displaysleepnow$"#
        ]
        
        for pattern in allowedPatterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    static func executeSystemCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCommandAllowed(trimmed) else {
            if !trimmed.isEmpty && trimmed.lowercased() != "none" {
                print("⚠️ [AIEngine Security] Blocked unauthorized command execution attempt: \(trimmed)")
            }
            return
        }
        
        print("⚡ [AIEngine Security Approved] Executing macOS System Command: \(trimmed)")
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", trimmed]
            try? task.run()
        }
    }
}

