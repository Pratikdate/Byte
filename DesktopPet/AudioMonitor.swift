import Foundation
import AVFoundation
import CoreAudio

class AudioMonitor: NSObject {
    static let shared = AudioMonitor()
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    
    // For rhythm / spike detection
    private var powerHistory: [Float] = []
    private let historyLimit = 20 // 2 seconds at 0.1s intervals
    
    
    var onLoudNoise: (() -> Void)?
    var onRhythmicMusic: (() -> Void)?
    
    var isHeadphoneConnected: Bool = false
    
    func startMonitoring() {
        // macOS doesn't use AVAudioSession like iOS. We just request permission via AVCaptureDevice or use it.
        if #available(macOS 10.14, *) {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                self.setupRecorder()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    if granted {
                        DispatchQueue.main.async {
                            self?.setupRecorder()
                        }
                    }
                }
            default:
                break
            }
        } else {
            setupRecorder()
        }
    }
    
    private func setupRecorder() {
        let url = URL(fileURLWithPath: "/dev/null")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.processAudioLevel()
            }
        } catch {
            print("Audio monitoring setup failed: \(error)")
        }
    }
    
    private func processAudioLevel() {
        guard let recorder = audioRecorder else { return }
        recorder.updateMeters()
        
        checkHeadphoneStatus()
        
        // peakPower ranges from -160 to 0 (db)
        let peakPower = recorder.peakPower(forChannel: 0)
        
        powerHistory.append(peakPower)
        if powerHistory.count > historyLimit {
            powerHistory.removeFirst()
        }
        
        // 1. Sudden Loud Noise (Startle)
        let recentAvg = powerHistory.dropLast().reduce(0, +) / Float(max(1, powerHistory.count - 1))
        
        if peakPower > -10 && (peakPower - recentAvg) > 20 {
            // Big sudden spike!
            onLoudNoise?()
            powerHistory.removeAll()
            return
        }
        
        // 2. Rhythmic Music (Dance)
        if powerHistory.count == historyLimit {
            var strongBeats = 0
            for power in powerHistory {
                if power > -20 {
                    strongBeats += 1
                }
            }
            if strongBeats >= 12 { // If sustained loud sounds for a while
                onRhythmicMusic?()
                powerHistory.removeAll()
            }
        }
    }
    
    private func checkHeadphoneStatus() {
        var defaultOutputDeviceID: AudioDeviceID = 0
        var defaultOutputSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultOutputPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputPropertyAddress,
            0,
            nil,
            &defaultOutputSize,
            &defaultOutputDeviceID
        )
        
        guard status == noErr else { return }
        
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString
        var deviceNamePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let nameStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &deviceNamePropertyAddress,
            0,
            nil,
            &nameSize,
            &deviceName
        )
        
        guard nameStatus == noErr else { return }
        
        let name = (deviceName as String).lowercased()
        isHeadphoneConnected = name.contains("headphone") || name.contains("airpod") || name.contains("buds") || name.contains("ear")
    }
}
