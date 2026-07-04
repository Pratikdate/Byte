import AppKit
import SwiftUI
import SceneKit
import SpriteKit // For the 2D screen material

class PetWindow: NSWindow {
    var acceptsKey: Bool = false
    override var canBecomeKey: Bool { return acceptsKey }
    override var canBecomeMain: Bool { return acceptsKey }
}

class PetSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept clicks if they actually hit the 3D pet model
        let localPoint = convert(point, from: superview)
        let hits = self.hitTest(localPoint, options: [:])
        
        // Ignore hits on the invisible SCNFloor (which is infinitely large)
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        
        if validHits.isEmpty {
            return nil // Click passes perfectly through to the desktop
        }
        
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        (scene as? PetScene)?.handleMouseDown(at: location, viewSize: bounds.size)
    }
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        (scene as? PetScene)?.handleMouseDragged(at: location, viewSize: bounds.size)
    }
    override func mouseUp(with event: NSEvent) {
        (scene as? PetScene)?.handleMouseUp()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    var scnView: PetSCNView!
    var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the transparent click-through overlay window
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        window = PetWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating // Always on top
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true // START COMPLETELY UNBLOCKING
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        // 3D SceneKit View
        scnView = PetSCNView(frame: window.frame)
        scnView.backgroundColor = .clear // Transparent background
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.wantsLayer = true
        scnView.layer?.isOpaque = false
        
        window.contentView = scnView
        
        let scene = PetScene()
        scnView.scene = scene
        scnView.isPlaying = true
        
        window.makeKeyAndOrderFront(nil)
        
        // Dynamically toggle click-through based on mouse position!
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
        
        setupKeyboardShortcuts()
    }
    
    private var shiftSHeld = false
    
    private func setupKeyboardShortcuts() {
        // Request macOS Accessibility permissions (needed to listen to global keystrokes)
        let options = ["AXTrustedCheckOptionPrompt" as NSString: true as NSNumber] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        print("🔒 Accessibility Trusted Status: \(isTrusted)")
        
        // Local keyboard monitor (runs when the app has focus)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let isShift = event.modifierFlags.contains(.shift)
            // Track S being held (keycode 1)
            if isShift && event.keyCode == 1 { self.shiftSHeld = true }
            // Shift+D = text chat (keycode 2)
            if isShift && event.keyCode == 2 {
                if self.shiftSHeld {
                    // Shift+S+D = voice input
                    self.shiftSHeld = false
                    self.startVoiceInput()
                } else {
                    self.presentChatPrompt()
                }
                return nil
            }
            return event
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 1 { self?.shiftSHeld = false }
            return event
        }
        
        // Global keyboard monitor (runs when other apps have focus)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let isShift = event.modifierFlags.contains(.shift)
            if isShift && event.keyCode == 1 { self.shiftSHeld = true }
            if isShift && event.keyCode == 2 {
                DispatchQueue.main.async {
                    if self.shiftSHeld {
                        self.shiftSHeld = false
                        self.startVoiceInput()
                    } else {
                        self.presentChatPrompt()
                    }
                }
            }
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 1 { self?.shiftSHeld = false }
        }
    }
    
    private func presentChatPrompt() {
        guard let scene = scnView.scene as? PetScene else { return }
        
        // Temporarily allow the window to accept keyboard focus
        window.acceptsKey = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = "Talk to your Desktop Pet"
        alert.informativeText = "What do you want to say to your pet?"
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.placeholderString = "Type message here..."
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        
        // Set focus to input field once the alert is ready
        DispatchQueue.main.async {
            self.window.makeFirstResponder(inputTextField)
        }
        
        let response = alert.runModal()
        
        // Reset window so it is click-through / ignores mouse and key events again
        window.acceptsKey = false
        window.ignoresMouseEvents = true
        
        if response == .alertFirstButtonReturn {
            let message = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                scene.sayToPet(message)
            }
        }
    }
    
    func checkMousePosition() {
        guard let window = window, let scnView = scnView, let scene = scnView.scene as? PetScene else { return }
        if scene.isDragging { return } // Never disable while dragging
        
        let mouseLoc = NSEvent.mouseLocation
        let localPoint = window.convertPoint(fromScreen: mouseLoc)
        let viewPoint = scnView.convert(localPoint, from: nil)
        
        let hits = scnView.hitTest(viewPoint, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        
        if !validHits.isEmpty {
            if window.ignoresMouseEvents {
                window.ignoresMouseEvents = false
            }
        } else {
            if !window.ignoresMouseEvents {
                window.ignoresMouseEvents = true
            }
        }
    }
}
