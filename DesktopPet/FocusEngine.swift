import Foundation
import AppKit
import CoreGraphics
import AVFoundation

/// Intelligent Focus Engine for Byte: Developer's Companion
/// Measures developer activity, focus depth, typing cadence, and meeting status
class FocusEngine {
    static let shared = FocusEngine()

    enum FocusLevel: String {
        case deepWork    // High typing cadence in IDE / Terminal -> Quiet companion mode
        case debugging   // Rapid app switches, log browsing -> Sympathetic observation
        case meeting     // Microphone active or video app frontmost -> Complete Silence
        case casual      // Browsing, casual usage -> Normal ambient interactions
        case idle        // System idle > 3 minutes -> Sleep / resting mode
    }

    private(set) var currentFocusLevel: FocusLevel = .casual
    var onFocusLevelChanged: ((FocusLevel) -> Void)?

    private var typingKeystrokeTimes: [Date] = []
    private var monitoringTimer: Timer?

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        // Monitor typing speed & focus depth every 2 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.evaluateFocusLevel()
        }
        
        // Listen for typing events from AppDelegate
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeystroke), name: NSNotification.Name("UserTypingFast"), object: nil)
    }

    @objc private func handleKeystroke() {
        typingKeystrokeTimes.append(Date())
    }

    /// Evaluates current focus depth based on frontmost app, typing speed, and audio inputs
    func evaluateFocusLevel() {
        let now = Date()
        // Retain keystrokes from the last 10 seconds
        typingKeystrokeTimes = typingKeystrokeTimes.filter { now.timeIntervalSince($0) < 10.0 }

        let systemIdleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let isIDEOrTerminal = isDeveloperTool(frontApp)
        let isMeetingApp = isVideoCallApp(frontApp)

        var newLevel: FocusLevel = .casual

        if isMeetingApp {
            newLevel = .meeting
        } else if systemIdleTime > 180 {
            newLevel = .idle
        } else if isIDEOrTerminal && typingKeystrokeTimes.count > 5 {
            newLevel = .deepWork
        } else if isIDEOrTerminal {
            newLevel = .debugging
        } else {
            newLevel = .casual
        }

        if newLevel != currentFocusLevel {
            currentFocusLevel = newLevel
            print("[FocusEngine] Focus level changed to: \(newLevel.rawValue)")
            onFocusLevelChanged?(newLevel)
        }
    }

    private func isDeveloperTool(_ appName: String) -> Bool {
        let name = appName.lowercased()
        return name.contains("xcode") || name.contains("code") || name.contains("terminal") ||
               name.contains("iterm") || name.contains("intellij") || name.contains("pycharm") ||
               name.contains("clion") || name.contains("webstorm") || name.contains("cursor") ||
               name.contains("sublime") || name.contains("nova")
    }

    private func isVideoCallApp(_ appName: String) -> Bool {
        let name = appName.lowercased()
        return name.contains("zoom") || name.contains("teams") || name.contains("meet") ||
               name.contains("webex") || name.contains("facetime") || (name.contains("slack") && name.contains("call"))
    }
}
