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
    
    private var isListening = false
    private var isShiftDDown = false
    
    private func setupKeyboardShortcuts() {
        // Request macOS Accessibility permissions (needed to listen to global keystrokes)
        let options = ["AXTrustedCheckOptionPrompt" as NSString: true as NSNumber] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // PUSH-TO-TALK: Hold Shift+D to record, release D to send.
        // No popups — completely seamless.
        
        // keyDown: start listening when Shift+D is first pressed
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.modifierFlags.contains(.shift) && event.keyCode == 2 && !event.isARepeat {
                self.beginListening()
                return nil
            }
            return event
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            if event.modifierFlags.contains(.shift) && event.keyCode == 2 && !event.isARepeat {
                DispatchQueue.main.async { self.beginListening() }
            }
        }
        
        // keyUp: release D key → stop listening and send transcript
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 2 && self.isListening {
                self.finishListening()
                return nil
            }
            return event
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == 2 && self.isListening {
                DispatchQueue.main.async { self.finishListening() }
            }
        }
        
        // Safety: if Shift is released mid-hold, also stop
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            if self.isListening && !event.modifierFlags.contains(.shift) {
                self.finishListening()
            }
            return event
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            if self.isListening && !event.modifierFlags.contains(.shift) {
                DispatchQueue.main.async { self.finishListening() }
            }
        }
    }
    
    private func beginListening() {
        guard !isListening else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListening = true
        
        // Pet shows it's listening
        scene.showListeningState(true)
        
        VoiceInputManager.shared.startListening { _ in }
    }
    
    private func finishListening() {
        guard isListening else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListening = false
        
        scene.showListeningState(false)
        
        let transcript = VoiceInputManager.shared.currentTranscript
        VoiceInputManager.shared.stopListening()
        
        if !transcript.isEmpty {
            scene.sayToPet(transcript)
        }
    }
    
    func checkMousePosition() {
        guard let window = window, let scnView = scnView, let scene = scnView.scene as? PetScene else { return }
        if scene.isDragging { return }
        
        let mouseLoc = NSEvent.mouseLocation
        let localPoint = window.convertPoint(fromScreen: mouseLoc)
        let viewPoint = scnView.convert(localPoint, from: nil)
        
        let hits = scnView.hitTest(viewPoint, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        
        if !validHits.isEmpty {
            if window.ignoresMouseEvents { window.ignoresMouseEvents = false }
        } else {
            if !window.ignoresMouseEvents { window.ignoresMouseEvents = true }
        }
    }
}
