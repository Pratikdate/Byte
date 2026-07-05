import Foundation
import GameplayKit
import CoreGraphics

// Keep the enums for the scene to map easily to animations/eyes
enum PetAction: String {
    case idle, wander, followCursor, sleep, jump, sit, spin, sulk, dizzy, tickled
    case peekWindow, sitOnTaskbar, investigate
    case stepBack, dance, bow, stretch, roll, hide, chaseLaser, seekTreat
}

enum PetEmotion: String {
    case happy, sad, angry, curious, sleepy, bored, thinking, normal, dizzy, shock, love, excited, embarrassed
}

enum PetMode: String {
    case auto = "Auto"
    case work = "Work"
    case play = "Play"
    case sleep = "Sleep"
}

// MARK: - GKAgent
class PetAgent: GKAgent2D {
    override init() {
        super.init()
        self.radius = 1.0
        self.maxSpeed = 7.0 // Exactly 1.4 units every 0.2 seconds to match leg stride!
        self.maxAcceleration = 50.0 // Reach max speed instantly to prevent sliding
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - GKStates
class PetBaseState: GKState {
    unowned let brain: PetBrain
    init(brain: PetBrain) { self.brain = brain }
}

class PetIdleState: PetBaseState {
    private var actionTimer: TimeInterval = 0
    private var nextActionTime: TimeInterval = 0
    
    override func didEnter(from previousState: GKState?) {
        // Don't overwrite one-off animations back to idle immediately
        let oneOffs: [PetAction] = [.jump, .spin, .sit, .sulk, .dizzy, .tickled, .dance, .bow, .stretch, .roll, .hide, .stepBack]
        if !oneOffs.contains(brain.currentAction) {
            brain.currentAction = .idle
        }
        actionTimer = 0
        // Make the idle time shorter so he decides to do things faster
        nextActionTime = TimeInterval.random(in: 1.0...4.0)
        brain.agent.behavior = nil // Stop moving
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        actionTimer += seconds
        
        // Every few seconds, score possible actions
        if actionTimer > nextActionTime {
            actionTimer = 0
            
            if brain.exploreCount > 0 {
                brain.exploreCount -= 1
                let nextActions: [PetAction] = [.wander, .jump, .spin, .investigate]
                let action = nextActions.randomElement()!
                
                // If it picked an animation, wait and then we will hit idle again and continue exploring.
                // If it picked wander, he walks immediately!
                brain.applyAction(action)
                nextActionTime = TimeInterval.random(in: 1.0...2.0)
            } else {
                nextActionTime = TimeInterval.random(in: 4.0...10.0) // Slower LLM loop to avoid spam
                if brain.isMuted {
                    // Fallback to offline lightweight logic when muted
                    brain.evaluateNextAction()
                } else {
                    // LLM takes complete control!
                    brain.requestLLMAction()
                }
            }
        }
    }
}

class PetWanderState: PetBaseState {
    private var wanderTime: TimeInterval = 0
    private var maxWanderTime: TimeInterval = 0
    private var targetX: CGFloat = 0
    private var targetY: CGFloat = 0
    
    override func didEnter(from previousState: GKState?) {
        if brain.currentEmotion != .bored {
            brain.currentEmotion = .curious
        }
        wanderTime = 0
        maxWanderTime = TimeInterval.random(in: 8...18)
        brain.agent.behavior = nil
        
        let elements = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .window }
        var targetedWindow = false
        
        if !elements.isEmpty && Double.random(in: 0...1) < 0.3 {
            if let targetWindow = elements.randomElement() {
                // Approximate screen to world mapping
                // Assuming main screen for simplicity
                // CGWindow coords: origin top-left
                let screenBounds = CGDisplayBounds(CGMainDisplayID())
                let screenW = screenBounds.width
                let screenH = screenBounds.height
                
                // We want to sit on top of the window, so Y is the minY of the frame
                let winX = targetWindow.frame.midX
                let winY = targetWindow.frame.minY
                
                // Map to SceneKit (-12.5 to 12.5 for X, 7 to -7 for Y roughly)
                targetX = (winX / screenW - 0.5) * 25.0
                targetY = (0.5 - winY / screenH) * 14.0
                targetedWindow = true
            }
        }
        
        if !targetedWindow {
            if brain.currentMode == .work && !brain.isMuted {
                let corner = brain.findFreeCorner()
                // Add randomness so he doesn't walk to the exact same pixel every time!
                targetX = corner.0 + CGFloat.random(in: -5.0...5.0)
                targetY = corner.1
            } else {
                let currentX = CGFloat(brain.agent.position.x)
                let goRight = currentX <= 0
                // Play/Auto mode: walk anywhere
                targetX = goRight ? CGFloat.random(in: 5.0...35.0) : CGFloat.random(in: -35.0...(-5.0))
                targetY = CGFloat.random(in: -10.0...10.0)
            }
        }
        
        brain.currentAction = .wander
        brain.onStartWalk?(targetX, targetY)
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        wanderTime += seconds
        brain.energy = max(0, brain.energy - (0.5 * seconds))
        
        // PetScene handles arrival detection — it enters PetIdleState when reached
        if wanderTime > maxWanderTime {
            stateMachine?.enter(PetIdleState.self)
        }
    }
}

class PetSleepState: PetBaseState {
    override func didEnter(from previousState: GKState?) {
        brain.currentAction = .sleep
        brain.currentEmotion = .sleepy
        brain.agent.behavior = nil
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        brain.energy = min(100, brain.energy + (5.0 * seconds))
        // Remains in sleep state indefinitely until user clicks to wake him up
    }
}

class PetInteractState: PetBaseState {
    private var timeInState: TimeInterval = 0
    
    override func didEnter(from previousState: GKState?) {
        brain.agent.behavior = nil
        timeInState = 0
        // Action/Emotion is set manually by PetScene (e.g. dizzy, tickled, drag)
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        timeInState += seconds
        
        // If user is just dragging, we stay here. If dizzy/tickled finishes, revert to idle.
        if !brain.isBeingDragged && timeInState > 3.0 {
            stateMachine?.enter(PetIdleState.self)
        }
    }
}

// MARK: - PetBrain
class PetBrain {
    var isGoingToSleep = false
    var currentMode: PetMode = .auto
    var exploreCount: Int = 0
    
    let agent = PetAgent()
    lazy var stateMachine = GKStateMachine(states: [
        PetIdleState(brain: self),
        PetWanderState(brain: self),
        PetSleepState(brain: self),
        PetInteractState(brain: self)
    ])
    
    var energy: Double = 100.0
    var mood: Double = 70.0
    var annoyance: Double = 0.0 // Needed for compilation in PetScene
    var boredom: Double = 0.0
    var curiosity: Double = 0.0
    
    // Properties polled by PetScene
    var currentAction: PetAction = .idle
    var currentEmotion: PetEmotion = .normal
    var isBeingDragged = false
    
    var onThoughtGenerated: ((String) -> Void)?
    var onStartWalk: ((CGFloat, CGFloat) -> Void)?  // Called by PetWanderState with target X and Y
    
    private var lastTickTime: TimeInterval = 0
    private var isQueryingAI = false
    var forceUpdate = false
    var isMuted = false
    
    init() {
        stateMachine.enter(PetIdleState.self) // Start idle — let AI decide what to do first
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ActiveAppChanged"), object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let appName = notification.object as? String else { return }
            
            // Wake up if sleeping and app changes
            if self.currentAction == .sleep {
                self.applyAction(.idle)
            }
            
            // Occasionally comment on the new app
            if Double.random(in: 0...1) < 0.3 {
                self.requestLLMAction()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("UserTypingFast"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if self.currentAction == .idle && Double.random(in: 0...1) < 0.4 {
                // If idle, occasionally dance to the typing rhythm
                self.triggerTypingDance()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func resolveEmotion() -> PetEmotion {
        if annoyance > 80 { return .angry }
        if energy < 15 { return .sleepy }
        if curiosity > 80 { return .curious }
        if mood > 70 && curiosity > 60 { return .happy }
        if mood < 30 { return .sad }
        if curiosity < 20 { return .bored }
        return .normal
    }
    var isListeningToUser: Bool = false
    
    func requestLLMAction(userMessage: String? = nil) {
        if isListeningToUser && userMessage == nil { return } // Prevent background chatter while listening
        if isQueryingAI { return }
        isQueryingAI = true
        
        let elements = DesktopEnvironmentManager.shared.visibleElements
        let activeWindows = elements.filter { $0.type == .window }.compactMap { $0.title }.joined(separator: ", ")
        
        let currentApp = DesktopEnvironmentManager.shared.activeAppTracker
        let timeActive = Date().timeIntervalSince(DesktopEnvironmentManager.shared.activeAppStartTime)
        let timeString = String(format: "%.0f", timeActive)
        
        let context = "Desktop has windows open: \(activeWindows.isEmpty ? "None" : activeWindows). The user is currently using \(currentApp) and has been for \(timeString) seconds."
        
        let emotionStr = String(describing: currentEmotion)
        let actions = ["idle", "wander", "sleep", "jump", "sit", "spin", "dance", "stretch", "roll"]
        
        // Show thinking while waiting
        currentEmotion = .thinking
        forceUpdate = true
        
        AIEngine.shared.generateAgentDecision(context: context, currentEmotion: emotionStr, availableActions: actions, userMessage: userMessage) { [weak self] decision in
            DispatchQueue.main.async {
                self?.isQueryingAI = false
                
                guard let decision = decision else {
                    // Fallback to basic random if LLM fails
                    self?.evaluateNextAction()
                    return
                }
                
                if let action = PetAction(rawValue: decision.action) {
                    self?.applyAction(action)
                } else {
                    self?.evaluateNextAction() // fallback
                }
                
                if let emotion = PetEmotion(rawValue: decision.emotion) {
                    self?.currentEmotion = emotion
                }
                
                if let memory = decision.store_memory {
                    MemoryGraph.shared.addFact(subject: memory.subject, predicate: memory.predicate, object: memory.object)
                }
                
                if !decision.speech.isEmpty && decision.speech != "..." && !(self?.isMuted ?? false) {
                    self?.onThoughtGenerated?(decision.speech)
                }
            }
        }
    }
    
    func evaluateNextAction() {
        if currentMode == .sleep {
            applyAction(.sleep)
            return
        }
        
        let elements = DesktopEnvironmentManager.shared.visibleElements
        let hasActiveWindows = !elements.filter({ $0.type == .window }).isEmpty
        
        // Auto mode logic: if windows are active, act like work mode
        let effectiveMode: PetMode
        if currentMode == .auto {
            let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
            effectiveMode = (idleTime < 10.0 && hasActiveWindows) ? .work : .play
        } else {
            effectiveMode = currentMode
        }
        
        var weights: [PetAction: Double] = [
            .idle: 40.0,
            .wander: 30.0,
            .sleep: 10.0,
            .jump: 5.0,
            .sit: 10.0,
            .spin: 5.0
        ]
        
        if effectiveMode == .work {
            // Work mode: prefer quiet, stay out of the way
            weights = [
                .idle: 50.0,
                .wander: 10.0, // wandering will route to free corner
                .sleep: 20.0,
                .sit: 20.0,
                .jump: 0.0,
                .spin: 0.0
            ]
        } else if effectiveMode == .play {
            // Play mode: active and wandering
            weights[.wander] = 50.0
            weights[.jump] = 20.0
            weights[.spin] = 10.0
            weights[.sleep] = 0.0
            weights[.idle] = 20.0
        }
        
        if isMuted {
            // When muted, prefer exploring rather than just standing idle
            weights[.wander] = (weights[.wander] ?? 0) + 40.0
            weights[.idle] = (weights[.idle] ?? 0) / 2.0
        }
        
        let bestAction = weights.max { a, b in a.value < b.value }?.key ?? .idle
        
        if effectiveMode == .play && bestAction == .wander && exploreCount == 0 {
            // Start an interesting exploration loop chaining 2-4 walks together
            exploreCount = Int.random(in: 2...4)
        }
        
        applyAction(bestAction)
    }
    
    func applyAction(_ action: PetAction) {
        currentAction = action
        currentEmotion = resolveEmotion()
        forceUpdate = true
        
        switch action {
        case .wander, .peekWindow, .sitOnTaskbar, .investigate, .chaseLaser, .seekTreat:
            stateMachine.enter(PetWanderState.self)
        case .sleep:
            // Don't sleep immediately. Wander to an extreme empty corner first.
            isGoingToSleep = true
            let (targetX, targetY) = findFreeCorner()
            onStartWalk?(targetX, targetY)
            currentAction = .wander
            stateMachine.enter(PetWanderState.self)
        case .idle:
            stateMachine.enter(PetIdleState.self)
        default:
            // One-off animations like jump, spin, sit, etc. just stay in idle logic essentially
            stateMachine.enter(PetIdleState.self)
        }
        
        // 20% chance to generate flavor text on any autonomous action change
        if Double.random(in: 0...1) < 0.20 {
            requestLLMAction()
        }
    }
    
    func notifyWalkFinished() {
        if isGoingToSleep {
            isGoingToSleep = false
            currentAction = .sleep
            currentEmotion = .sleepy
            stateMachine.enter(PetSleepState.self)
            forceUpdate = true
        } else {
            currentAction = .idle
            stateMachine.enter(PetIdleState.self)
        }
    }
    
    // For when the user clicks 'Talk to me'
    func queryAI(userMessage: String? = nil) {
        requestLLMAction(userMessage: userMessage)
    }
    
    // Allows forcing an animation for testing via the menu bar
    func forceAction(_ action: PetAction) {
        applyAction(action)
    }
    
    func tick(currentTime: TimeInterval, cursorMoved: Bool) -> (action: PetAction, emotion: PetEmotion, changed: Bool) {
        let dt = lastTickTime == 0 ? 0.016 : currentTime - lastTickTime
        lastTickTime = currentTime
        
        let oldAction = currentAction
        let oldEmotion = currentEmotion
        let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
        if idleTime > 25.0 {
            if currentAction == .idle {
                isGoingToSleep = true
                let (targetX, targetY) = findFreeCorner()
                onStartWalk?(targetX, targetY)
                currentAction = .wander
                currentEmotion = .sleepy
                stateMachine.enter(PetWanderState.self)
            }
        }
        
        // Constantly decay/grow state variables slightly to make them dynamic
        energy = min(100, max(0, energy + (currentAction == .sleep ? 1.0 : -0.1) * dt))
        curiosity = min(100, max(0, curiosity + (currentAction == .wander ? -0.2 : 0.1) * dt))
        annoyance = min(100, max(0, annoyance - 0.2 * dt))
        mood = min(100, max(0, mood + (currentAction == .sleep ? 0.0 : -0.05) * dt))
        
        // Every tick, passively evaluate if our emotion should change based on variables
        if currentEmotion != .thinking && currentEmotion != .shock && currentEmotion != .dizzy {
            let newlyResolvedEmotion = resolveEmotion()
            if newlyResolvedEmotion != currentEmotion && Double.random(in: 0...1) < 0.1 {
                currentEmotion = newlyResolvedEmotion
            }
        }
        
        stateMachine.update(deltaTime: dt)
        agent.update(deltaTime: dt)
        
        let changed = (oldAction != currentAction) || (oldEmotion != currentEmotion) || forceUpdate
        if forceUpdate { forceUpdate = false }
        return (currentAction, currentEmotion, changed)
    }
    
    func triggerDizzy() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .dizzy
        currentEmotion = .dizzy
    }
    
    func triggerTickle() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .tickled
        currentEmotion = .happy
    }
    
    func triggerStartle() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .jump
        currentEmotion = .shock
    }
    
    func triggerPetting() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .dance
        currentEmotion = .love
        mood = min(100, mood + 10)
    }
    
    func triggerEating() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .bow
        currentEmotion = .happy
        energy = min(100, energy + 30)
    }
    
    func triggerTypingDance() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .dance
        currentEmotion = .excited
        mood = min(100, mood + 5)
    }
    
    func setDragged(_ dragged: Bool) {
        forceUpdate = true
        isBeingDragged = dragged
        if dragged {
            stateMachine.enter(PetInteractState.self)
            currentAction = .sulk
            currentEmotion = .angry
        } else {
            stateMachine.enter(PetIdleState.self)
        }
    }
    
    // Finds an empty corner on the screen in world coordinates
    func findFreeCorner() -> (CGFloat, CGFloat) {
        let screenBounds = CGDisplayBounds(CGMainDisplayID())
        let screenW = screenBounds.width
        let screenH = screenBounds.height
        
        let corners = [
            CGPoint(x: screenW * 0.1, y: screenH * 0.1), // Top-Left
            CGPoint(x: screenW * 0.9, y: screenH * 0.1), // Top-Right
            CGPoint(x: screenW * 0.1, y: screenH * 0.9), // Bottom-Left
            CGPoint(x: screenW * 0.9, y: screenH * 0.9)  // Bottom-Right
        ]
        
        let windows = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .window }
        
        var bestCorner = corners[2] // Default to bottom-left
        
        for corner in corners {
            let intersects = windows.contains { $0.frame.contains(corner) }
            if !intersects {
                bestCorner = corner
                break
            }
        }
        
        // Map to SceneKit
        // Using wider bounds for edge-to-edge (-35 to 35 for X, 15 to -15 for Y)
        let targetX = (bestCorner.x / screenW - 0.5) * 70.0
        let targetY = (0.5 - bestCorner.y / screenH) * 30.0
        
        return (targetX, targetY)
    }
}
