import Foundation
import AVFoundation

/// Wraps faster-whisper (local speech-to-text) + Kokoro TTS (local speech synthesis)
/// All processing runs on-device, no cloud dependency.
class AudioManager {
    static let shared = AudioManager()

    private let whisperEndpoint = "http://localhost:9000/transcribe"
    private let kokoroEndpoint = "http://localhost:8880/synthesize"
    private let personaplexEndpoint = "http://localhost:9006/synthesize_speech"

    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private let audioQueue = DispatchQueue(label: "com.byte.audio.queue")

    var onTranscriptionUpdate: ((String) -> Void)?
    var onTranscriptionFinished: ((String) -> Void)?
    var onSpeakingFinished: (() -> Void)?

    private(set) var isListening = false
    private(set) var isSpeaking = false

    private var accumulatedAudio = Data()
    private var lastSendTime = Date.distantPast
    /// Only one live-partial request at a time. Each one re-sends the whole utterance so
    /// far; firing every 0.5s regardless piled up requests faster than Whisper could
    /// answer them, so every one timed out and the server pinned the CPU.
    private var partialInFlight = false

    func startListening() {
        guard !isListening else { return }
        isListening = true

        SystemSTT.shared.onTranscriptionUpdate = { [weak self] text in
            DispatchQueue.main.async {
                self?.onTranscriptionUpdate?(text)
            }
        }

        SystemSTT.shared.onTranscriptionFinished = { [weak self] text in
            DispatchQueue.main.async {
                self?.onTranscriptionFinished?(text)
            }
        }

        SystemSTT.shared.startListening()

        // Also run PCM capture in parallel as backup for Whisper
        audioQueue.async {
            self.accumulatedAudio.removeAll()
            self.lastSendTime = Date()
            self.partialInFlight = false
            self.captureAudioAndTranscribe()
        }
    }

    func stopListening() {
        isListening = false

        SystemSTT.shared.stopListeningAndTranscribe { [weak self] systemText in
            guard let self = self else { return }

            if self.audioEngine.isRunning {
                try? self.audioEngine.stop()
            }
            let inputNode = self.audioEngine.inputNode
            inputNode.removeTap(onBus: 0)

            let cleanSystemText = systemText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanSystemText.isEmpty {
                print("[AudioManager] System STT captured: '\(cleanSystemText)'")
                DispatchQueue.main.async {
                    self.onTranscriptionFinished?(cleanSystemText)
                }
            } else {
                print("[AudioManager] System STT empty or stalled, falling back to Whisper server on port 9000...")
                self.forceSendAudioToWhisper()
            }
        }
    }

    private func forceSendAudioToWhisper() {
        let dataToSend = self.accumulatedAudio
        guard let url = URL(string: self.whisperEndpoint) else {
            DispatchQueue.main.async {
                self.onTranscriptionFinished?("")
            }
            return
        }

        var request = URLRequest(url: url.appendingQuery("final=1"))
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = dataToSend
        // The accurate model needs ~3s for a 4s sentence on a Mac CPU; 2.5s always timed out.
        request.timeoutInterval = 10.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cleanWhisperText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[AudioManager] Whisper server returned: '\(cleanWhisperText)'")
                DispatchQueue.main.async {
                    self.onTranscriptionUpdate?(cleanWhisperText)
                    self.onTranscriptionFinished?(cleanWhisperText)
                }
            } else {
                print("[AudioManager] Whisper fallback empty or unreachable.")
                DispatchQueue.main.async {
                    self.onTranscriptionFinished?("")
                }
            }
        }.resume()
    }

    private var audioConverter: AVAudioConverter?

    /// Stream microphone → faster-whisper for real-time transcription
    private func captureAudioAndTranscribe() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            print("[AudioManager] Failed to create 16kHz format")
            DispatchQueue.main.async {
                self.isListening = false
            }
            return
        }

        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)

        // Remove any existing tap before installing new one
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.audioConverter else { return }

            let capacity = UInt32(Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate)
            // Add a little padding to capacity just in case
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity + 1024) else { return }

            var error: NSError?
            var allDone = false
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                if allDone {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allDone = true
                outStatus.pointee = .haveData
                return buffer
            }

            if status != .error && status != .endOfStream {
                self.sendAudioToWhisper(convertedBuffer)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("[AudioManager] Audio engine failed: \(error)")
            DispatchQueue.main.async {
                self.isListening = false
            }
        }
    }

    /// POST PCM buffer to faster-whisper server
    private func sendAudioToWhisper(_ buffer: AVAudioPCMBuffer) {
        guard isListening else { return }

        // Safely extract audio data from buffer
        let audioBufferList = buffer.audioBufferList
        let audioBuffer = audioBufferList.pointee.mBuffers

        guard let pcmData = audioBuffer.mData else {
            print("[AudioManager] No PCM data in buffer")
            return
        }

        let frameLength = Int(buffer.frameLength)
        let bytesPerFrame = Int(audioBuffer.mDataByteSize) / max(frameLength, 1)
        let totalBytes = frameLength * bytesPerFrame

        let audioData = Data(bytes: pcmData, count: totalBytes)

        audioQueue.async { [weak self] in
            guard let self = self, self.isListening else { return }
            self.accumulatedAudio.append(audioData)

            let now = Date()
            if self.partialInFlight || now.timeIntervalSince(self.lastSendTime) < 0.5 {
                return
            }
            self.lastSendTime = now
            self.partialInFlight = true

            let dataToSend = self.accumulatedAudio

            // Build request safely
            guard let url = URL(string: self.whisperEndpoint) else {
                print("[AudioManager] Invalid whisper endpoint URL")
                return
            }

            var request = URLRequest(url: url.appendingQuery("final=0"))   // fast model for live text
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = dataToSend
            request.timeoutInterval = 6.0

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            self.audioQueue.async { self.partialInFlight = false }

            if let error = error {
                print("[AudioManager] Whisper request error: \(error.localizedDescription)")
                return
            }

            guard let data = data, !data.isEmpty else {
                print("[AudioManager] No data from whisper server")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String,
                   !text.isEmpty {
                    // A live partial: show it, but never end listening on it (the server used
                    // to mark every reply final, which cut the user off mid-sentence).
                    DispatchQueue.main.async {
                        self.onTranscriptionUpdate?(text)
                    }
                }
            } catch {
                print("[AudioManager] Failed to parse whisper response: \(error)")
            }
        }.resume()
        }
    }

    /// Immediately stop any in-progress speech (barge-in for user interaction).
    func stopSpeaking() {
        downloadQueue.removeAll()
        readyAudioQueue.removeAll()
        audioQueue.async {
            self.audioPlayer?.stop()
        }
        SystemTTSFallback.shared.stop()
        isSpeaking = false
        isDownloading = false
    }

    private var downloadQueue: [(String, String, Float)] = []
    private var readyAudioQueue: [Data] = []
    private var isDownloading = false
    
    /// Generate speech with Kokoro TTS or fallback to system TTS
    /// - Parameter interrupt: if true, cut off any current speech first (used for user-directed replies)
    func speak(_ text: String, emotion: String = "neutral", speed: Float = 1.0, interrupt: Bool = false) {
        guard !text.isEmpty else { return }

        if interrupt {
            stopSpeaking()
        }

        downloadQueue.append((text, emotion, speed))
        processDownloadQueue()
    }

    private func processDownloadQueue() {
        guard !isDownloading, !downloadQueue.isEmpty else { return }

        let (text, emotion, speed) = downloadQueue.removeFirst()
        isDownloading = true

        let payload: [String: Any] = [
            "text": text,
            "emotion": emotion,
            "speed": speed,
            "voice_id": "am_onyx" // American Male TTS voice profile
        ]

        // Try Kokoro endpoint first, then PersonaPlex endpoint (port 9006), then System TTS
        let targetEndpoint = URL(string: kokoroEndpoint) ?? URL(string: personaplexEndpoint)!

        var request = URLRequest(url: targetEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("[AudioManager] Failed to serialize TTS payload: \(error)")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // Only a 200 with real WAV bytes counts. Anything else (a connection error, or
            // another app on the port answering 405 with JSON) used to be "played" as audio,
            // which failed silently and left Byte mute.
            guard error == nil, status == 200, let audioData = data, Self.isWAV(audioData) else {
                print("[AudioManager] Kokoro returned no audio (HTTP \(status), \(error?.localizedDescription ?? "not WAV")). Trying fallback voice.")
                self.speakWithFallback(text, emotion: emotion, speed: speed)
                return
            }

            self.enqueueSynthesizedAudio(audioData)
        }.resume()
    }

    private static func isWAV(_ data: Data) -> Bool {
        return data.count > 44 && data.prefix(4) == Data("RIFF".utf8)
    }

    private func enqueueSynthesizedAudio(_ audioData: Data) {
        DispatchQueue.main.async {
            self.readyAudioQueue.append(audioData)
            self.isDownloading = false
            self.processDownloadQueue() // keep downloading next items in background!
            self.processPlaybackQueue() // trigger playback if it's idle
        }
    }

    /// Kokoro failed. Use PersonaPlex only if it's running a real model (in mock mode it
    /// returns placeholder tones, not speech); otherwise speak with the macOS voice.
    private func speakWithFallback(_ text: String, emotion: String, speed: Float) {
        guard let healthURL = URL(string: "http://localhost:9006/health"),
              let synthURL = URL(string: personaplexEndpoint) else {
            speakWithSystemVoice(text, emotion: emotion)
            return
        }

        var healthReq = URLRequest(url: healthURL)
        healthReq.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: healthReq) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let isMock = json?["is_mock"] as? Bool, !isMock else {
                self.speakWithSystemVoice(text, emotion: emotion)
                return
            }

            var pReq = URLRequest(url: synthURL)
            pReq.httpMethod = "POST"
            pReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            pReq.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "speed": speed])
            pReq.timeoutInterval = 5.0
            URLSession.shared.dataTask(with: pReq) { pData, pResp, pErr in
                if pErr == nil, (pResp as? HTTPURLResponse)?.statusCode == 200,
                   let audioData = pData, Self.isWAV(audioData) {
                    self.enqueueSynthesizedAudio(audioData)
                } else {
                    self.speakWithSystemVoice(text, emotion: emotion)
                }
            }.resume()
        }.resume()
    }

    private func speakWithSystemVoice(_ text: String, emotion: String) {
        print("[AudioManager] Using macOS system voice")
        DispatchQueue.main.async {
            self.isSpeaking = true
            SystemTTSFallback.shared.speak(text, emotion: emotion) {
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.isDownloading = false
                    if self.readyAudioQueue.isEmpty && self.downloadQueue.isEmpty {
                        self.onSpeakingFinished?()
                    }
                    self.processDownloadQueue()
                }
            }
        }
    }

    private func processPlaybackQueue() {
        guard !isSpeaking, !readyAudioQueue.isEmpty else { return }
        
        let audioData = readyAudioQueue.removeFirst()
        isSpeaking = true
        playAudioData(audioData)
    }

    /// Play audio bytes from TTS server
    private func playAudioData(_ audioData: Data) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else {
            print("[AudioManager] Failed to create audio format for playback")
            isSpeaking = false
            processPlaybackQueue()
            return
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tts_\(UUID().uuidString).wav")

        do {
            try audioData.write(to: tempURL)

            let audioFile = try AVAudioFile(forReading: tempURL)
            let playerNode = AVAudioPlayerNode()

            // Detach any existing player nodes to prevent resource leaks
            if let existingPlayer = audioPlayer {
                audioEngine.detach(existingPlayer)
            }

            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)

            try audioEngine.start()
            playerNode.play()
            try playerNode.scheduleFile(audioFile, at: nil)

            audioPlayer = playerNode

            // Calculate duration with precision
            let sampleRate = Double(audioFile.processingFormat.sampleRate)
            let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 1.0

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.isSpeaking = false
                if self.readyAudioQueue.isEmpty && self.downloadQueue.isEmpty {
                    self.onSpeakingFinished?()
                }

                // Clean up
                playerNode.stop()
                try? FileManager.default.removeItem(at: tempURL)
                
                self.processPlaybackQueue()
            }
        } catch {
            print("[AudioManager] Audio playback error: \(error)")
            isSpeaking = false
            try? FileManager.default.removeItem(at: tempURL)
            processPlaybackQueue()
        }
    }
}

private extension URL {
    func appendingQuery(_ query: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.query = [components.query, query].compactMap { $0 }.joined(separator: "&")
        return components.url ?? self
    }
}
