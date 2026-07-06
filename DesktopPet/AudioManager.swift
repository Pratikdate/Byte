import Foundation
import AVFoundation

/// Wraps faster-whisper (local speech-to-text) + Kokoro TTS (local speech synthesis)
/// All processing runs on-device, no cloud dependency.
class AudioManager {
    static let shared = AudioManager()

    private let whisperEndpoint = "http://localhost:9000/transcribe"
    private let kokoroEndpoint = "http://localhost:8000/synthesize"

    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private let audioQueue = DispatchQueue(label: "com.byte.audio.queue")

    var onTranscriptionUpdate: ((String) -> Void)?
    var onTranscriptionFinished: ((String) -> Void)?
    var onSpeakingFinished: (() -> Void)?

    private(set) var isListening = false
    private(set) var isSpeaking = false

    func startListening() {
        guard !isListening else { return }

        audioQueue.async {
            self.isListening = true
            self.captureAudioAndTranscribe()
        }
    }

    func stopListening() {
        audioQueue.async {
            self.isListening = false
            if self.audioEngine.isRunning {
                try? self.audioEngine.stop()
            }
            let inputNode = self.audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
        }
    }

    /// Stream microphone → faster-whisper for real-time transcription
    private func captureAudioAndTranscribe() {
        let inputNode = audioEngine.inputNode

        // Get audio format or use default
        guard let format = inputNode.outputFormat(forBus: 0) ?? AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else {
            print("[AudioManager] Failed to create audio format")
            DispatchQueue.main.async {
                self.isListening = false
            }
            return
        }

        // Remove any existing tap before installing new one
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.sendAudioToWhisper(buffer)
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

        // Build request safely
        guard let url = URL(string: whisperEndpoint) else {
            print("[AudioManager] Invalid whisper endpoint URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, self.isListening else { return }

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
                    DispatchQueue.main.async {
                        self.onTranscriptionUpdate?(text)
                        if json["is_final"] as? Bool == true {
                            self.onTranscriptionFinished?(text)
                        }
                    }
                }
            } catch {
                print("[AudioManager] Failed to parse whisper response: \(error)")
            }
        }.resume()
    }

    /// Immediately stop any in-progress speech (barge-in for user interaction).
    func stopSpeaking() {
        audioQueue.async {
            self.audioPlayer?.stop()
        }
        SystemTTSFallback.stop()
        isSpeaking = false
    }

    /// Generate speech with Kokoro TTS or fallback to system TTS
    /// - Parameter interrupt: if true, cut off any current speech first (used for user-directed replies)
    func speak(_ text: String, emotion: String = "neutral", speed: Float = 1.0, interrupt: Bool = false) {
        guard !text.isEmpty else { return }

        if interrupt {
            stopSpeaking()
        } else {
            // Non-urgent speech yields if Byte is already talking (avoids overlap).
            guard !isSpeaking else { return }
        }

        isSpeaking = true

        let payload: [String: Any] = [
            "text": text,
            "emotion": emotion,
            "speed": speed,
            "voice_id": "default"
        ]

        guard let url = URL(string: kokoroEndpoint) else {
            print("[AudioManager] Invalid Kokoro endpoint URL")
            DispatchQueue.main.async {
                SystemTTSFallback.speak(text, emotion: emotion)
                self.isSpeaking = false
                self.onSpeakingFinished?()
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("[AudioManager] Failed to serialize Kokoro payload: \(error)")
            DispatchQueue.main.async {
                SystemTTSFallback.speak(text, emotion: emotion)
                self.isSpeaking = false
                self.onSpeakingFinished?()
            }
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Fallback to system TTS if Kokoro unavailable
            if error != nil || data == nil {
                print("[AudioManager] Kokoro TTS unavailable, using system TTS")
                DispatchQueue.main.async {
                    SystemTTSFallback.speak(text, emotion: emotion)
                    self.isSpeaking = false
                    self.onSpeakingFinished?()
                }
                return
            }

            guard let audioData = data else {
                print("[AudioManager] No audio data from Kokoro")
                DispatchQueue.main.async {
                    self.isSpeaking = false
                }
                return
            }

            DispatchQueue.main.async {
                self.playAudioData(audioData)
            }
        }.resume()
    }

    /// Play audio bytes from TTS server
    private func playAudioData(_ audioData: Data) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else {
            print("[AudioManager] Failed to create audio format for playback")
            isSpeaking = false
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
                self.onSpeakingFinished?()

                // Clean up
                playerNode.stop()
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            print("[AudioManager] Audio playback error: \(error)")
            isSpeaking = false
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
