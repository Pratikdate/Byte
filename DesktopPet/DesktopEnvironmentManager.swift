import Foundation
import AppKit
import ApplicationServices

struct DesktopElement {
    enum ElementType {
        case window
        case taskbar
        case desktopIcon
        case notification
    }
    
    let type: ElementType
    let frame: CGRect
    let title: String?
}

class DesktopEnvironmentManager {
    static let shared = DesktopEnvironmentManager()
    
    var visibleElements: [DesktopElement] = []
    
    var frontmostWindowTitle: String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else { return nil }
        
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                if let ownerName = window[kCGWindowOwnerName as String] as? String, ownerName == appName {
                    if let title = window[kCGWindowName as String] as? String, !title.isEmpty {
                        return "\(appName) - \(title)"
                    }
                }
            }
        }
        return appName
    }
    
    var activeAppTracker: String = ""
    var activeAppStartTime: Date = Date()
    
    private func trackActiveApp() {
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else { return }
        
        if appName != activeAppTracker {
            activeAppTracker = appName
            activeAppStartTime = Date()
            NotificationCenter.default.post(name: NSNotification.Name("ActiveAppChanged"), object: appName)
        }
    }
    
    private var timer: Timer?
    
    // Check if we have accessibility permissions
    var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }
    
    func startMonitoring() {
        if !hasAccessibilityPermission {
            // Prompt user for accessibility, this will show a system dialog if not granted
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String : true]
            AXIsProcessTrustedWithOptions(options)
        }
        
        // Seed immediately with fallback to prevent launch drop
        var initialElements: [DesktopElement] = []
        fallbackDock(elements: &initialElements)
        visibleElements = initialElements
        
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshEnvironment()
        }
        timer?.fire()
    }
    
    private func refreshEnvironment() {
        trackActiveApp()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var elements: [DesktopElement] = []
            
            // 1. Get Windows (using CoreGraphics)
            if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                for window in windowList {
                    if let ownerName = window[kCGWindowOwnerName as String] as? String, ownerName == "DesktopPet" { continue }
                    
                    // Get window layer, normal windows are 0
                    if let layer = window[kCGWindowLayer as String] as? Int, layer < 100 {
                        if let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                           let x = boundsDict["X"], let y = boundsDict["Y"],
                           let width = boundsDict["Width"], let height = boundsDict["Height"] {
                            
                            let rect = CGRect(x: x, y: y, width: width, height: height)
                            let title = window[kCGWindowName as String] as? String
                            elements.append(DesktopElement(type: .window, frame: rect, title: title))
                        }
                    }
                }
            }
            
            // 2. Get Dock (Taskbar)
            let dockPID = self?.getDockPID() ?? 0
            if dockPID > 0 {
                let dockElement = AXUIElementCreateApplication(dockPID)
                var axFrame: CFTypeRef?
                if AXUIElementCopyAttributeValue(dockElement, "AXFrame" as CFString, &axFrame) == .success {
                    var rect = CGRect.zero
                    if AXValueGetValue(axFrame as! AXValue, .cgRect, &rect) {
                        elements.append(DesktopElement(type: .taskbar, frame: rect, title: "Dock"))
                    }
                } else {
                    self?.fallbackDock(elements: &elements)
                }
            } else {
                self?.fallbackDock(elements: &elements)
            }
            
            DispatchQueue.main.async {
                self?.visibleElements = elements
            }
        }
    }

    
    private func fallbackDock(elements: inout [DesktopElement]) {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let screenHeight = screen.frame.height
            let screenWidth = screen.frame.width
            
            if frame.minY > 0 { // Dock is on bottom
                let dockHeight = frame.minY
                let dockWidth = screenWidth * 0.8 // Estimate 80% width
                let dockX = (screenWidth - dockWidth) / 2.0
                // Convert to CGWindow coords (top-left origin)
                let dockY = screenHeight - dockHeight
                
                let rect = CGRect(x: dockX, y: dockY, width: dockWidth, height: dockHeight)
                elements.append(DesktopElement(type: .taskbar, frame: rect, title: "Dock"))
            }
        }
    }
    
    private func getDockPID() -> Int32 {
        let workspace = NSWorkspace.shared
        let dockApps = workspace.runningApplications.filter { $0.bundleIdentifier == "com.apple.dock" }
        return dockApps.first?.processIdentifier ?? 0
    }
}
