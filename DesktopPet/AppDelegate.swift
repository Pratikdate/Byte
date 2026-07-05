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
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let hits = self.hitTest(location, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        if !validHits.isEmpty {
            return .copy
        }
        return []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let location = convert(sender.draggingLocation, from: nil)
        let hits = self.hitTest(location, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        if !validHits.isEmpty {
            (scene as? PetScene)?.brain.triggerEating()
            return true
        }
        return false
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    var scnView: PetSCNView!
    var updateTimer: Timer?
    var statusItem: NSStatusItem?
    var emotionUpdateTimer: Timer?

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
        scnView.registerForDraggedTypes([.fileURL])
        
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
        
        // Start Downloads Watcher
        DownloadsWatcher.shared.startWatching()
        
        // Menu bar emotion icon updater (every 2 seconds)
        emotionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarEmotion()
        }
    }
    
    // MARK: - Menu Bar Emotion Icon
    private func updateMenuBarEmotion() {
        guard let scene = scnView?.scene as? PetScene else { return }
        let emotion = scene.brain.currentEmotion
        let emoji = emotionToEmoji(emotion)
        
        if let button = statusItem?.button {
            button.image = nil
            button.title = emoji
        }
    }
    
    private func emotionToEmoji(_ emotion: PetEmotion) -> String {
        switch emotion {
        case .happy:        return "😊"
        case .sad:          return "😢"
        case .angry:        return "😤"
        case .curious:      return "🧐"
        case .sleepy:       return "😴"
        case .bored:        return "😑"
        case .thinking:     return "🤔"
        case .normal:       return "🤖"
        case .dizzy:        return "😵"
        case .shock:        return "😱"
        case .love:         return "😍"
        case .excited:      return "🤩"
        case .embarrassed:  return "😳"
        }
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
        
        let dropTreatItem = NSMenuItem(title: "🍬 Drop Treat", action: #selector(dropTreat(_:)), keyEquivalent: "t")
        menu.addItem(dropTreatItem)
        
        // Pet Modes Sub-Menu
        let modesMenu = NSMenu()
        modesMenu.addItem(NSMenuItem(title: "Auto (Smart)", action: #selector(setModeAuto(_:)), keyEquivalent: ""))
        modesMenu.addItem(NSMenuItem(title: "Work Mode (Quiet/Corner)", action: #selector(setModeWork(_:)), keyEquivalent: ""))
        modesMenu.addItem(NSMenuItem(title: "Play Mode (Active/Wander)", action: #selector(setModePlay(_:)), keyEquivalent: ""))
        modesMenu.addItem(NSMenuItem(title: "Sleep Mode", action: #selector(setModeSleep(_:)), keyEquivalent: ""))
        
        let modesMenuItem = NSMenuItem(title: "⚙️ Pet Mode", action: nil, keyEquivalent: "")
        modesMenuItem.submenu = modesMenu
        menu.addItem(modesMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let muteItem = NSMenuItem(title: "🔇 Mute Pet", action: #selector(toggleMute(_:)), keyEquivalent: "m")
        menu.addItem(muteItem)
        
        let cloudAIItem = NSMenuItem(title: "☁️ Use Cloud AI (Gemini API)", action: #selector(toggleCloudAI(_:)), keyEquivalent: "")
        cloudAIItem.state = .off
        menu.addItem(cloudAIItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Test Animations Sub-Menu
        let animationsMenu = NSMenu()
        let animations: [(String, Int)] = [
            ("Idle", 0), ("Wander / Walk", 1), ("Sleep", 3), ("Jump", 4),
            ("Sit", 5), ("Spin", 6), ("Sulk", 7), ("Dizzy", 8), ("Tickled", 9),
            ("Peek Window", 10), ("Sit on Taskbar", 11), ("Investigate", 12),
            ("Step Back", 13), ("Dance", 14), ("Bow", 15), ("Stretch", 16),
            ("Roll", 17), ("Hide", 18)
        ]
        
        for (name, tag) in animations {
            let item = NSMenuItem(title: name, action: #selector(testAnimationClicked(_:)), keyEquivalent: "")
            item.tag = tag
            animationsMenu.addItem(item)
        }
        
        let animationsMenuItem = NSMenuItem(title: "🎬 Test Animations", action: nil, keyEquivalent: "")
        animationsMenuItem.submenu = animationsMenu
        menu.addItem(animationsMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Desktop Pet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func testAnimationClicked(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        let actions: [PetAction] = [
            .idle, .wander, .followCursor, .sleep, .jump, .sit, .spin, .sulk, .dizzy, .tickled,
            .peekWindow, .sitOnTaskbar, .investigate, .stepBack, .dance, .bow, .stretch, .roll, .hide
        ]
        if sender.tag >= 0 && sender.tag < actions.count {
            scene.brain.forceAction(actions[sender.tag])
        }
    }
    
    @objc private func toggleMute(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        scene.isMuted.toggle()
        scene.brain.isMuted = scene.isMuted
        sender.state = scene.isMuted ? .on : .off
    }
    
    @objc private func toggleCloudAI(_ sender: NSMenuItem) {
        let isCurrentlyCloud = sender.state == .on
        if isCurrentlyCloud {
            AIEngine.shared.provider = LocalOllamaProvider()
            sender.state = .off
        } else {
            AIEngine.shared.provider = GeminiAPIProvider(apiKey: "AQ.Ab8RN6JquuZTkTTYuwK4u8G1zZeUG6NXcKmWbqVohVFvSbyawA")
            sender.state = .on
        }
    }
    
    @objc private func dropTreat(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        scene.dropTreat()
    }
    
    @objc private func setModeAuto(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .auto
    }
    
    @objc private func setModeWork(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .work
    }
    
    @objc private func setModePlay(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .play
    }
    
    @objc private func setModeSleep(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .sleep
    }
    
    // MARK: - Keyboard Shortcuts
    private var isListeningForPet = false     // Long Command: talk to pet
    private var commandPressTime: Date?       // Tracks when Command was first pressed
    private var commandLongPressTimer: Timer?  // Timer for long-press detection
    private var otherKeyPressed = false        // Tracks if another key was pressed during Command hold
    
    private var eventMonitors: [Any?] = []
    private var keystrokeDates: [Date] = []
    
    private func trackKeystroke() {
        let now = Date()
        keystrokeDates.append(now)
        // Keep only keystrokes from the last 3 seconds
        keystrokeDates = keystrokeDates.filter { now.timeIntervalSince($0) < 3.0 }
        
        if keystrokeDates.count > 15 {
            // Typing fast! (avg > 5 keys/sec over 3 seconds)
            NotificationCenter.default.post(name: NSNotification.Name("UserTypingFast"), object: nil)
            keystrokeDates.removeAll() // Reset to avoid spam
        }
    }
    
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
        // and track typing speed
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            self.trackKeystroke()
            if event.modifierFlags.contains(.command) {
                self.otherKeyPressed = true
                self.commandLongPressTimer?.invalidate()
            }
            return event
        })
        
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            self.trackKeystroke()
            if event.modifierFlags.contains(.command) {
                self.otherKeyPressed = true
                self.commandLongPressTimer?.invalidate()
            }
        })
    }
    
    // MARK: - Command Long-Press Detection (Talk to Pet)
    private func handleFlagsChanged(_ event: NSEvent) {
        let commandDown = event.modifierFlags.contains(.command)
        let optionDown = event.modifierFlags.contains(.option)
        
        if let scene = scnView?.scene as? PetScene {
            scene.isLaserPointerActive = optionDown
        }
        
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
    
    // MARK: - Voice Input (Command Long-Press)
    private func beginPetListening() {
        guard !isListeningForPet else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListeningForPet = true
        scene.brain.isListeningToUser = true
        scene.showListeningState(true)
        VoiceInputManager.shared.startListening { _ in }
    }
    
    private func finishPetListening() {
        guard isListeningForPet else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListeningForPet = false
        scene.brain.isListeningToUser = false
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
        
        // Fullscreen auto-hide: fade out when a fullscreen app is frontmost
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            // Check if frontmost app is fullscreen by examining its windows
            let isFullscreen = NSApp.presentationOptions.contains(.fullScreen)
            let isSelf = frontApp.bundleIdentifier == Bundle.main.bundleIdentifier
            
            if isFullscreen && !isSelf {
                if window.alphaValue > 0.01 {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.3
                        window.animator().alphaValue = 0.0
                    }
                }
                return  // Don't process mouse events while hidden
            } else if window.alphaValue < 0.99 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    window.animator().alphaValue = 1.0
                }
            }
        }
        
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
