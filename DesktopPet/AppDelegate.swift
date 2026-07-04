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
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        window = PetWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.hasShadow = false
        
        scnView = PetSCNView(frame: screenRect)
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.wantsLayer = true
        scnView.layer?.isOpaque = false
        
        window.contentView = scnView
        
        let scene = PetScene()
        scnView.scene = scene
        scnView.isPlaying = true
        
        window.makeKeyAndOrderFront(nil)
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
        
        setupMenuBar()
        setupKeyboardShortcuts()
    }
    
    // MARK: - Menu Bar Settings
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Desktop Pet")
            // Fallback if symbol not available
            if button.image == nil {
                button.title = "🐾"
            }
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🤖 Desktop Pet Settings", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Feature list
        let features = [
            ("🎤 Talk to Pet", "Hold D, speak, release to send"),
            ("📝 Voice Dictation", "Long press ⌘ (0.6s), speak, release to type"),
            ("🖱️ Drag Pet", "Click and drag the pet anywhere"),
            ("👆 Pet / Tickle", "Click on the pet"),
            ("👀 Pet Awareness", "Pet watches your mouse and active apps"),
        ]
        
        for (title, shortcut) in features {
            let item = NSMenuItem()
            item.title = "\(title)  —  \(shortcut)"
            item.isEnabled = false
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Desktop Pet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    // MARK: - Keyboard Shortcuts
    private var isListeningForPet = false     // Long Command: talk to pet
    private var commandPressTime: Date?       // Tracks when Command was first pressed
    private var commandLongPressTimer: Timer?  // Timer for long-press detection
    private var otherKeyPressed = false        // Tracks if another key was pressed during Command hold
    
    private var eventMonitors: [Any?] = []
    
    private func setupKeyboardShortcuts() {
        let options = ["AXTrustedCheckOptionPrompt" as NSString: true as NSNumber] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // === FLAGS CHANGED: Detect Command press/release for long-press to talk to pet ===
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            self.handleFlagsChanged(event)
            return event
        })
        
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.handleFlagsChanged(event)
            }
        })
        
        // Detect if any other key is pressed during Command hold to cancel it
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.modifierFlags.contains(.command) {
                self.otherKeyPressed = true
                self.commandLongPressTimer?.invalidate()
            }
            return event
        })
        
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            if event.modifierFlags.contains(.command) {
                self.otherKeyPressed = true
                self.commandLongPressTimer?.invalidate()
            }
        })
    }
    
    // MARK: - Command Long-Press Detection (Talk to Pet)
    private func handleFlagsChanged(_ event: NSEvent) {
        let commandDown = event.modifierFlags.contains(.command)
        
        if commandDown && commandPressTime == nil && !isListeningForPet {
            // Command just pressed — start long-press timer
            commandPressTime = Date()
            otherKeyPressed = false
            commandLongPressTimer?.invalidate()
            commandLongPressTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if !self.otherKeyPressed && !self.isListeningForPet {
                    self.beginPetListening()
                }
            }
        } else if !commandDown {
            // Command released
            commandLongPressTimer?.invalidate()
            commandLongPressTimer = nil
            commandPressTime = nil
            
            if isListeningForPet {
                finishPetListening()
            }
        }
    }
    
    // MARK: - Shift+D: Talk to Pet
    private func beginPetListening() {
        guard !isListeningForPet else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListeningForPet = true
        scene.showListeningState(true)
        VoiceInputManager.shared.startListening { _ in }
    }
    
    private func finishPetListening() {
        guard isListeningForPet else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListeningForPet = false
        scene.showListeningState(false)
        
        VoiceInputManager.shared.finishListeningWithResult { transcript in
            if !transcript.isEmpty {
                scene.sayToPet(transcript)
            }
        }
    }
    
    // MARK: - Mouse Position Check
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
