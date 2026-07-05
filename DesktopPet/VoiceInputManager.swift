import Foundation
import Speech
import AVFoundation

class VoiceInputManager {
    static let shared = VoiceInputManager()
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var onTranscriptionUpdate: ((String) -> Void)?
    var onFinishedTranscribing: ((String) -> Void)?
    private(set) var currentTranscript: String = ""
    
    func startListening(completion: @escaping (Bool) -> Void) {
        currentTranscript = "" // Reset on new session
        // Request Speech Recognition permission
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                guard authStatus == .authorized else {
                    completion(false)
                    return
                }
                
                // Request Microphone permission (macOS compatible)
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            completion(false)
                            return
                        }
                        
                        do {
                            try self.startRecording()
                            completion(true)
                        } catch {
                            print("Audio Engine failed to start: \(error)")
                            completion(false)
                        }
                    }
                }
            }
        }
    }
    
    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    func finishListeningWithResult(completion: @escaping (String) -> Void) {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Give the speech recognizer 0.6 seconds to process the final words
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let final = self.currentTranscript
            self.recognitionRequest = nil
            self.recognitionTask = nil
            completion(final)
        }
    }
    
    private func startRecording() throws {
        // Cancel any active tasks
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let inputNode = audioEngine.inputNode
        
        // CRITICAL FIX: Always explicitly remove any lingering tap before installing a new one 
        // to prevent "nullptr == Tap()" crash!
        inputNode.removeTap(onBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                self.currentTranscript = transcription
                self.onTranscriptionUpdate?(transcription)
                
                if result.isFinal {
                    self.onFinishedTranscribing?(transcription)
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.stopListening()
            }
        }
    }
}
