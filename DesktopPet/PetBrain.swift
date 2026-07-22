import Foundation
import GameplayKit
import CoreGraphics
import UserNotifications

// Keep the enums for the scene to map easily to animations/eyes
enum PetAction: String {
    case idle, wander, followCursor, sleep, jump, sit, spin, sulk, dizzy, tickled
    case peekWindow, sitOnTaskbar, investigate
    case stepBack, dance, bow, stretch, roll, hide, chaseLaser, seekTreat
    // New interactive actions
    case sitOnCorner, sitOnMenuBar, climbWindow, pushWidget, tapWindow
    case sneeze, backflip, headbang, trip, wave
}

enum PetEmotion: String {
    case happy, sad, angry, curious, sleepy, bored, thinking, normal, dizzy, shock, love, excited, embarrassed
    case proud
    case singing, working, cold, hot, tictactoe, fishing, dj, batteryLow, dreaming, coffee, rainy
}

enum PetMode: String {
    case auto = "Auto"
    case work = "Work"
    case play = "Play"
    case sleep = "Sleep"
}

// MARK: - Time-of-Day Routine Phases (Spec §7)
enum PetRoutinePhase: String {
    case earlyMorning  // 5am-8am: groggy, waking up
    case morning       // 8am-12pm: alert, curious
    case lunch         // 12pm-1pm: playful, social
    case afternoon     // 1pm-5pm: focused, work-mode leaning
    case evening       // 5pm-9pm: relaxed, winding down
    case night         // 9pm-11pm: sleepy, calm
    case lateNight     // 11pm-5am: very sleepy, wants to sleep
    
    static func current() -> PetRoutinePhase {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8:   return .earlyMorning
        case 8..<12:  return .morning
        case 12..<13: return .lunch
        case 13..<17: return .afternoon
        case 17..<21: return .evening
        case 21..<23: return .night
        default:      return .lateNight  // 11pm-5am
        }
    }
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
        let oneOffs: [PetAction] = [.jump, .spin, .sit, .sulk, .dizzy, .tickled, .dance, .bow, .stretch, .roll, .hide, .stepBack, .sneeze, .backflip, .headbang, .trip, .wave, .tapWindow, .pushWidget]
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
                let nextActions: [PetAction] = [.wander, .jump, .spin, .investigate, .backflip, .wave]
                let action = nextActions.randomElement()!
                
                // If it picked an animation, wait and then we will hit idle again and continue exploring.
                // If it picked wander, he walks immediately!
                brain.applyAction(action)
                nextActionTime = TimeInterval.random(in: 1.0...2.0)
            } else {
                // Pace autonomy to the user's attention: back off when they're idle/away.
                switch InteractionDirector.shared.currentAttention() {
                case .away:
                    nextActionTime = TimeInterval.random(in: 120.0...240.0)
                case .idle:
                    nextActionTime = TimeInterval.random(in: 90.0...180.0)
                default:
                    nextActionTime = TimeInterval.random(in: 60.0...120.0)
                }
                brain.requestAmbientAction()
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
                let currentState = brain.getCurrentSector()
                let nextAction = QLearningManager.shared.chooseAction(state: currentState)
                let (tx, ty) = brain.getCoordinatesForSector(nextAction)
                targetX = tx
                targetY = ty
                brain.lastQState = currentState
                brain.lastQAction = nextAction
                brain.didQWander = true
            }
        } else {
            brain.didQWander = false
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
        
        // Trigger self-reflection feedback loop when going to sleep
        ReflectionEngine.shared.performReflection { success in
            if success {
                print("ReflectionEngine: Byte successfully learned from recent feedback.")
            }
        }
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
    
    // Routine Phase (Spec §7)
    var currentRoutinePhase: PetRoutinePhase = .morning
    
    // Q-Learning Tracking
    var lastQState: Int?
    var lastQAction: Int?
    var didQWander: Bool = false
    
    private var lastRoutineCheck: TimeInterval = 0
    
    // Emotion Transition Guard (Spec §8 — no instant extreme flips)
    private var lastEmotionChangeTime: TimeInterval = 0
    private let emotionCooldown: TimeInterval = 1.5

    // Emotional momentum: a new feeling must persist before it takes over (no random jitter).
    private var emotionCandidate: PetEmotion = .normal
    private var emotionCandidateSince: TimeInterval = 0

    // Particle callbacks (set by PetScene)
    var onShowParticle: ((ParticleType) -> Void)?
    
    var onSentenceGenerated: ((String) -> Void)?
    var onSpeechComplete: (() -> Void)?
    var onStartWalk: ((CGFloat, CGFloat) -> Void)?  // Called by PetWanderState with target X and Y
    
    private var lastTickTime: TimeInterval = 0
    private var isQueryingAI = false
    // Monotonic query id: a newer request invalidates older in-flight ones (no stale/queued replies).
    private var queryGeneration = 0
    var forceUpdate = false
    var isMuted = false
    var isTrainingMode = false
    
    init() {
        stateMachine.enter(PetIdleState.self) // Start idle — let AI decide what to do first
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ActiveAppChanged"), object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let appName = notification.object as? String else { return }
            
            // App-specific reactions
            let lowerApp = appName.lowercased()
            if lowerApp.contains("music") || lowerApp.contains("spotify") {
                self.applyAction(.headbang)
            } else if lowerApp.contains("safari") || lowerApp.contains("chrome") || lowerApp.contains("browser") {
                self.applyAction(.peekWindow)
            }
            
            // Wake up if sleeping and app changes
            if self.currentAction == .sleep {
                self.applyAction(.idle)
            }
            
            // Occasionally comment on the new app — reactive event, but respect attention.
            if Double.random(in: 0...1) < 0.3 && InteractionDirector.shared.shouldSpeak(.reactive) {
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

        
        // Start Audio & Weather Monitoring
        AudioMonitor.shared.startMonitoring()
        AudioMonitor.shared.onLoudNoise = { [weak self] in
            if self?.currentAction == .sleep {
                self?.applyAction(.jump)
                self?.currentEmotion = .shock
            } else {
                self?.triggerStartle()
            }
        }
        AudioMonitor.shared.onRhythmicMusic = { [weak self] in
            if self?.currentAction == .idle || self?.currentAction == .wander {
                self?.applyAction(.dance)
            }
        }
        
        WeatherManager.shared.startMonitoring()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func resolveEmotion() -> PetEmotion {
        // Priority order: Annoyed > Energy depletion > High Curiosity > Proud/Happy > Low Mood > Normal
        if annoyance > 80 { return .angry }
        if energy < 15 { return .sleepy }
        if curiosity > 80 { return .curious }
        if mood > 85 && energy > 70 { return .proud }
        if mood > 60 { return .happy }
        if mood < 30 { return .sad }
        if curiosity < 20 { return .bored }
        return .normal
    }
    var isListeningToUser: Bool = false

    /// Autonomous "what should I do next" tick, paced by how present the user is.
    /// Quiet/local behavior when the user is idle or away; LLM-driven when they're around.
    func requestAmbientAction() {
        switch InteractionDirector.shared.currentAttention() {
        case .away, .idle:
            // Present-but-quiet: pick a gentle local behavior, no LLM chatter.
            evaluateNextAction()
        case .active, .engaged, .returning:
            if isMuted {
                evaluateNextAction()
            } else {
                requestLLMAction()
            }
        }
    }

    func requestLLMAction(userMessage: String? = nil) {
        let isUserDirected = (userMessage != nil && !(userMessage?.isEmpty ?? true))

        if isListeningToUser && !isUserDirected { return } // Prevent background chatter while listening
        // A user-directed message always gets through — never dropped behind an ambient query.
        if isQueryingAI && !isUserDirected { return }

        if isUserDirected {
            // Barge-in: cut off any ambient speech so the reply feels immediate, not queued.
            AudioManager.shared.stopSpeaking()
            InteractionDirector.shared.recordUserTurn(userMessage!)
        }

        // Bump generation so any older in-flight request is discarded when it returns.
        queryGeneration += 1
        let myGeneration = queryGeneration
        isQueryingAI = true

        let elements = DesktopEnvironmentManager.shared.visibleElements
        let activeWindows = elements.filter { $0.type == .window }.compactMap { $0.title }.joined(separator: ", ")
        
        let currentApp = DesktopEnvironmentManager.shared.activeAppTracker
        let timeActive = Date().timeIntervalSince(DesktopEnvironmentManager.shared.activeAppStartTime)
        let timeString = String(format: "%.0f", timeActive)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy 'at' h:mm a"
        let dateString = formatter.string(from: Date())
        
        let weatherStr = WeatherManager.shared.isRaining ? "It is raining outside." : "The weather is clear."
        let context = "The current date and time is \(dateString). \(weatherStr) Desktop has windows open: \(activeWindows.isEmpty ? "None" : activeWindows). The user is currently using \(currentApp) and has been for \(timeString) seconds."
        
        let emotionStr = String(describing: currentEmotion)
        let actions = ["idle", "wander", "sleep", "jump", "sit", "spin", "dance", "stretch", "roll", "sitOnCorner", "sitOnMenuBar", "climbWindow", "pushWidget", "tapWindow", "sneeze", "backflip", "headbang", "wave"]
        
        // Show thinking while waiting
        currentEmotion = .thinking
        forceUpdate = true
        
        AIEngine.shared.generateAgentDecisionStreaming(
            context: context, 
            currentEmotion: emotionStr, 
            availableActions: actions, 
            userMessage: userMessage,
            onAction: { [weak self] decision in
                guard let self = self else { return }
                if myGeneration != self.queryGeneration { return }
                
                if decision.target_x != nil || decision.target_y != nil {
                    let tx = decision.target_x.map { CGFloat($0) }
                    let ty = decision.target_y.map { CGFloat($0) }
                    self.handleSpatialCommand(action: decision.action, targetX: tx, targetY: ty)
                } else if let action = PetAction(rawValue: decision.action) {
                    self.applyAction(action)
                } else {
                    self.evaluateNextAction()
                }

                if let emotion = PetEmotion(rawValue: decision.emotion) {
                    self.currentEmotion = emotion
                }
            },
            onSentence: { [weak self] sentence in
                guard let self = self else { return }
                if myGeneration != self.queryGeneration { return }
                
                if !sentence.isEmpty && sentence != "..." {
                    InteractionDirector.shared.noteSpoke(sentence)
                    InteractionDirector.shared.consumeReturnGreeting()
                    self.onSentenceGenerated?(sentence)
                }
            },
            onComplete: { [weak self] in
                guard let self = self else { return }
                if myGeneration != self.queryGeneration { return }
                self.isQueryingAI = false
                self.onSpeechComplete?()
            }
        )
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
        
        let state = ReinforcementLearningModel.shared.getCurrentState()
        let isWorkMode = (effectiveMode == .work)
        
        let bestAction = ReinforcementLearningModel.shared.chooseAction(state: state, isWorkMode: isWorkMode, isMuted: isMuted)
        

        if effectiveMode == .play && bestAction == .wander && exploreCount == 0 {
            // Start an interesting exploration loop chaining 2-4 walks together
            exploreCount = Int.random(in: 2...4)
        }
        
        applyAction(bestAction)
    }
    
    // Callback for spatial commands (set by PetScene)
    var onSpatialCommand: ((PetAction, CGFloat, CGFloat) -> Void)?
    
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
        // New spatial actions — walk to a target then perform the action
        case .sitOnCorner:
            let (tx, ty) = findNearestCorner()
            currentEmotion = .normal
            onSpatialCommand?(action, tx, ty)
            stateMachine.enter(PetWanderState.self)
        case .sitOnMenuBar:
            let (tx, ty) = findMenuBarPosition()
            currentEmotion = .curious
            onSpatialCommand?(action, tx, ty)
            stateMachine.enter(PetWanderState.self)
        case .climbWindow:
            let (tx, ty) = findNearestWindowTop()
            currentEmotion = .excited
            onSpatialCommand?(action, tx, ty)
            stateMachine.enter(PetWanderState.self)
        case .pushWidget:
            let (tx, ty) = findNearestWindowEdge()
            currentEmotion = .excited
            onSpatialCommand?(action, tx, ty)
            stateMachine.enter(PetWanderState.self)
        case .tapWindow:
            let (tx, ty) = findNearestWindowEdge()
            currentEmotion = .curious
            onSpatialCommand?(action, tx, ty)
            stateMachine.enter(PetWanderState.self)
        // One-off personality animations
        case .sneeze:
            currentEmotion = .shock
            stateMachine.enter(PetInteractState.self)
        case .backflip:
            currentEmotion = .excited
            stateMachine.enter(PetInteractState.self)
        case .headbang:
            currentEmotion = .excited
            stateMachine.enter(PetInteractState.self)
        case .trip:
            currentEmotion = .embarrassed
            stateMachine.enter(PetInteractState.self)
        case .wave:
            currentEmotion = .happy
            stateMachine.enter(PetInteractState.self)
        default:
            // One-off animations like jump, spin, sit, etc. just stay in idle logic essentially
            stateMachine.enter(PetIdleState.self)
        }
        
        // Occasional flavor text on autonomous action change — only when the user is present.
        if Double.random(in: 0...1) < 0.20 {
            let attention = InteractionDirector.shared.currentAttention()
            if attention == .active || attention == .engaged || attention == .returning {
                requestLLMAction()
            }
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
            if didQWander, let state = lastQState, let action = lastQAction {
                let nextState = getCurrentSector()
                triggerFeedbackNotification(state: state, action: action, nextState: nextState)
                didQWander = false
            }
            
            currentAction = .idle
            stateMachine.enter(PetIdleState.self)
        }
    }
    
    private func triggerFeedbackNotification(state: Int, action: Int, nextState: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Byte's Walk"
        content.body = "Byte walked to a new spot! Was this a good path?"
        content.categoryIdentifier = "WALK_FEEDBACK"
        
        content.userInfo = ["state": state, "action": action, "nextState": nextState]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding feedback notification: \\(error)")
            }
        }
    }
    
    // MARK: - Q-Learning Sector Helpers
    
    func getCurrentSector() -> Int {
        // Assume scene X bounds are roughly -35 to 35, Y bounds -10 to 10
        let x = CGFloat(agent.position.x)
        let y = CGFloat(agent.position.y)
        
        let col: Int
        if x < -11.6 { col = 0 }
        else if x > 11.6 { col = 2 }
        else { col = 1 }
        
        let row: Int
        if y < -3.3 { row = 2 }
        else if y > 3.3 { row = 0 }
        else { row = 1 }
        
        return row * 3 + col
    }
    
    func getCoordinatesForSector(_ sector: Int) -> (CGFloat, CGFloat) {
        let row = sector / 3
        let col = sector % 3
        
        let tx: CGFloat
        switch col {
        case 0: tx = CGFloat.random(in: -35.0...(-11.6))
        case 1: tx = CGFloat.random(in: -11.6...11.6)
        default: tx = CGFloat.random(in: 11.6...35.0)
        }
        
        let ty: CGFloat
        switch row {
        case 0: ty = CGFloat.random(in: 3.3...10.0)
        case 1: ty = CGFloat.random(in: -3.3...3.3)
        default: ty = CGFloat.random(in: -10.0...(-3.3))
        }
        
        return (tx, ty)
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
        
        // Update routine phase every 30 seconds (no need to compute every tick)
        if currentTime - lastRoutineCheck > 30.0 {
            lastRoutineCheck = currentTime
            let newPhase = PetRoutinePhase.current()
            if newPhase != currentRoutinePhase {
                currentRoutinePhase = newPhase
                // Phase transition — ambient time-of-day remark, gated by attention.
                if !isMuted && Double.random(in: 0...1) < 0.5 && InteractionDirector.shared.shouldSpeak(.ambient) {
                    requestLLMAction()
                }
            }
        }
        
        // Battery / CPU integration from EnvironmentMonitor
        if EnvironmentMonitor.shared.isBatteryLow {
            energy = min(energy, 40.0)  // Cap energy when battery is low
            if Double.random(in: 0...1) < 0.002 {
                onShowParticle?(.sweat)
            }
        }
        if EnvironmentMonitor.shared.isCPUHigh {
            mood = max(0, mood - 0.3 * dt)  // Mood dips under thermal pressure
            if Double.random(in: 0...1) < 0.005 {
                onShowParticle?(.sweat)
            }
        }
        
        // Late night auto-sleep (routine-driven)
        let isLateNight = (currentRoutinePhase == .lateNight)
        if isLateNight && idleTime > 15.0 && currentAction == .idle {
            isGoingToSleep = true
            let (targetX, targetY) = findFreeCorner()
            onStartWalk?(targetX, targetY)
            currentAction = .wander
            currentEmotion = .sleepy
            stateMachine.enter(PetWanderState.self)
        } else if idleTime > 25.0 {
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
        // Routine phase modulates energy drain rate
        let energyDrain: Double
        switch currentRoutinePhase {
        case .lateNight, .night: energyDrain = -0.25  // Drains faster at night
        case .earlyMorning:     energyDrain = -0.15
        case .lunch:            energyDrain = -0.05   // Lunch break, less drain
        default:                energyDrain = -0.1
        }
        energy = min(100, max(0, energy + (currentAction == .sleep ? 1.0 : energyDrain) * dt))
        curiosity = min(100, max(0, curiosity + (currentAction == .wander ? -0.2 : 0.1) * dt))
        annoyance = min(100, max(0, annoyance - 0.2 * dt))
        mood = min(100, max(0, mood + (currentAction == .sleep ? 0.0 : -0.05) * dt))
        
        // Emotional momentum (replaces the old random 10%/tick flip).
        // A newly-resolved feeling must PERSIST for a dwell time before it takes over,
        // so moods have inertia — Byte stays sad/happy/curious for a while, then shifts
        // deliberately instead of jittering. Reactive states (thinking/shock/dizzy) are
        // owned elsewhere and skipped here.
        if currentEmotion != .thinking && currentEmotion != .shock && currentEmotion != .dizzy {
            let resolved = resolveEmotion()

            if resolved == currentEmotion {
                // Already feeling this — reset any pending candidate.
                emotionCandidate = currentEmotion
                emotionCandidateSince = currentTime
            } else {
                // A different feeling is being pushed by the state variables.
                if resolved != emotionCandidate {
                    // New candidate — start its dwell clock.
                    emotionCandidate = resolved
                    emotionCandidateSince = currentTime
                }

                // Strong feelings assert faster; subtle ones need to linger.
                let strong: Set<PetEmotion> = [.angry, .sleepy, .sad]
                let dwell: TimeInterval = strong.contains(resolved) ? 1.5 : 3.5

                let persisted = (currentTime - emotionCandidateSince) >= dwell
                let cooledDown = (currentTime - lastEmotionChangeTime) > emotionCooldown

                if persisted && cooledDown {
                    // Extreme flips pass through neutral first (no angry→love snap).
                    let extremes: Set<PetEmotion> = [.angry, .love, .excited]
                    if extremes.contains(oldEmotion) && extremes.contains(resolved) && oldEmotion != resolved {
                        currentEmotion = .normal
                    } else {
                        currentEmotion = resolved
                    }
                    lastEmotionChangeTime = currentTime
                }
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
    
    // MARK: - Downloads Curiosity
    func triggerCuriosity(about fileName: String) {
        curiosity = min(100, curiosity + 40)
        mood = min(100, mood + 5)
        forceUpdate = true
        currentEmotion = .curious
        onShowParticle?(.sparkle)
        
        // Reactive event — comment only if the user is around to notice.
        if !isMuted && InteractionDirector.shared.shouldSpeak(.reactive) {
            let context = "A new file just appeared in the user's Downloads folder: \(fileName)"
            AIEngine.shared.generateComment(context: context, emotion: "curious") { [weak self] comment in
                DispatchQueue.main.async {
                    if let comment = comment {
                        self?.onSentenceGenerated?(comment)
                        self?.onSpeechComplete?()
                    }
                }
            }
        }
        
        // Walk towards a random spot (simulating "investigating")
        applyAction(.investigate)
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
    
    // MARK: - Spatial Awareness Helpers
    
    /// Finds the closest screen corner to Byte's current position
    func findNearestCorner() -> (CGFloat, CGFloat) {
        let currentX = CGFloat(agent.position.x)
        let currentY = CGFloat(agent.position.y)
        
        var maxX: CGFloat = 15.0
        if let screen = NSScreen.main {
            let aspect = screen.frame.width / screen.frame.height
            maxX = 7.0 * aspect
        }
        
        // Four corners in world coordinates
        let corners: [(CGFloat, CGFloat)] = [
            (-maxX + 2.0, 6.0),    // Top-Left
            (maxX - 2.0, 6.0),     // Top-Right
            (-maxX + 2.0, -3.2),   // Bottom-Left
            (maxX - 2.0, -3.2)     // Bottom-Right
        ]
        
        var closest = corners[0]
        var minDist = CGFloat.greatestFiniteMagnitude
        for c in corners {
            let d = hypot(c.0 - currentX, c.1 - currentY)
            if d < minDist {
                minDist = d
                closest = c
            }
        }
        return closest
    }
    
    /// Finds the farthest screen corner from Byte's current position
    func findFarthestCorner() -> (CGFloat, CGFloat) {
        let currentX = CGFloat(agent.position.x)
        let currentY = CGFloat(agent.position.y)
        
        var maxX: CGFloat = 15.0
        if let screen = NSScreen.main {
            let aspect = screen.frame.width / screen.frame.height
            maxX = 7.0 * aspect
        }
        
        let corners: [(CGFloat, CGFloat)] = [
            (-maxX + 2.0, 6.0),
            (maxX - 2.0, 6.0),
            (-maxX + 2.0, -3.2),
            (maxX - 2.0, -3.2)
        ]
        
        var farthest = corners[0]
        var maxDist: CGFloat = 0
        for c in corners {
            let d = hypot(c.0 - currentX, c.1 - currentY)
            if d > maxDist {
                maxDist = d
                farthest = c
            }
        }
        return farthest
    }
    
    /// Returns world position for the menu bar (top of screen)
    func findMenuBarPosition() -> (CGFloat, CGFloat) {
        let currentX = CGFloat(agent.position.x)
        // Menu bar is at the very top of the screen in world coords
        // Y ~6.5 puts Byte right at the top edge
        return (currentX, 6.5)
    }
    
    /// Finds the top edge of the nearest visible window in world coords
    func findNearestWindowTop() -> (CGFloat, CGFloat) {
        let screenBounds = CGDisplayBounds(CGMainDisplayID())
        let screenW = screenBounds.width
        let screenH = screenBounds.height
        let currentX = CGFloat(agent.position.x)
        let currentY = CGFloat(agent.position.y)
        
        let windows = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .window }
        
        var closestDist = CGFloat.greatestFiniteMagnitude
        var bestX: CGFloat = 0
        var bestY: CGFloat = 2.0
        
        for window in windows {
            // Map window top-center to world coords
            let winCenterX = window.frame.midX
            let winTopY = window.frame.minY  // CGWindow has top-left origin
            
            let worldX = (winCenterX / screenW - 0.5) * 25.0
            let worldY = (0.5 - winTopY / screenH) * 14.0
            
            let d = hypot(worldX - currentX, worldY - currentY)
            if d < closestDist {
                closestDist = d
                bestX = worldX
                bestY = worldY + 0.5  // Sit slightly above the window top
            }
        }
        
        return (bestX, bestY)
    }
    
    /// Finds the nearest window side edge to walk up to
    func findNearestWindowEdge() -> (CGFloat, CGFloat) {
        let screenBounds = CGDisplayBounds(CGMainDisplayID())
        let screenW = screenBounds.width
        let screenH = screenBounds.height
        let currentX = CGFloat(agent.position.x)
        let currentY = CGFloat(agent.position.y)
        
        let windows = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .window }
        
        var closestDist = CGFloat.greatestFiniteMagnitude
        var bestX: CGFloat = 5.0
        var bestY: CGFloat = -3.2
        
        for window in windows {
            // Pick the left or right edge depending on which is closer
            let leftEdgeX = window.frame.minX
            let rightEdgeX = window.frame.maxX
            let midY = window.frame.midY
            
            let worldLeftX = (leftEdgeX / screenW - 0.5) * 25.0 - 1.0
            let worldRightX = (rightEdgeX / screenW - 0.5) * 25.0 + 1.0
            let worldY = (0.5 - midY / screenH) * 14.0
            
            let dLeft = hypot(worldLeftX - currentX, worldY - currentY)
            let dRight = hypot(worldRightX - currentX, worldY - currentY)
            
            if dLeft < closestDist {
                closestDist = dLeft
                bestX = worldLeftX
                bestY = worldY
            }
            if dRight < closestDist {
                closestDist = dRight
                bestX = worldRightX
                bestY = worldY
            }
        }
        
        return (bestX, bestY)
    }
    
    // MARK: - New Trigger Methods
    
    func triggerSneeze() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .sneeze
        currentEmotion = .shock
        onShowParticle?(.sparkle)
    }
    
    func triggerTrip() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .trip
        currentEmotion = .embarrassed
    }
    
    func triggerWave() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .wave
        currentEmotion = .happy
        mood = min(100, mood + 5)
    }
    
    func triggerProud() {
        forceUpdate = true
        currentEmotion = .proud
        onShowParticle?(.sparkle)
    }
    
    func triggerBackflip() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .backflip
        currentEmotion = .excited
        onShowParticle?(.sparkle)
    }
    
    func triggerHeadbang() {
        forceUpdate = true
        stateMachine.enter(PetInteractState.self)
        currentAction = .headbang
        currentEmotion = .excited
    }
    
    /// Handles a spatial command from the AI (e.g. "go sit in corner")
    func handleSpatialCommand(action: String, targetX: CGFloat?, targetY: CGFloat?) {
        guard let petAction = PetAction(rawValue: action) else {
            evaluateNextAction()
            return
        }
        
        // If AI provided coordinates, use them; otherwise let applyAction figure it out
        if let tx = targetX, let ty = targetY {
            onSpatialCommand?(petAction, tx, ty)
            currentAction = petAction
            currentEmotion = resolveEmotion()
            forceUpdate = true
            stateMachine.enter(PetWanderState.self)
        } else {
            applyAction(petAction)
        }
    }
}

// MARK: - QLearningManager

class QLearningManager {
    static let shared = QLearningManager()
    
    // Hyperparameters
    private let alpha: Double = 0.1   // Learning rate
    private let gamma: Double = 0.9   // Discount factor
    private let epsilon: Double = 0.2 // Exploration rate
    
    // Q-Table mapping "state_action" -> Q-Value
    private var qTable: [String: Double] = [:]
    
    // We assume 9 sectors (0 to 8) in a 3x3 grid
    private let numStates = 9
    private let numActions = 9
    
    private let userDefaultsKey = "PetQTable"
    
    private init() {
        loadQTable()
    }
    
    private func getQValue(state: Int, action: Int) -> Double {
        let key = "\(state)_\(action)"
        return qTable[key] ?? 0.0
    }
    
    private func setQValue(state: Int, action: Int, value: Double) {
        let key = "\(state)_\(action)"
        qTable[key] = value
    }
    
    /// Chooses the next sector to walk to based on epsilon-greedy policy
    func chooseAction(state: Int) -> Int {
        if Double.random(in: 0...1) < epsilon {
            // Explore: Pick a random action
            return Int.random(in: 0..<numActions)
        } else {
            // Exploit: Pick the action with the highest Q-value for the current state
            var bestAction = 0
            var maxQValue = -Double.greatestFiniteMagnitude
            
            // Collect all actions with the max Q-value to break ties randomly
            var bestActions: [Int] = []
            
            for action in 0..<numActions {
                let qVal = getQValue(state: state, action: action)
                if qVal > maxQValue {
                    maxQValue = qVal
                    bestActions = [action]
                } else if abs(qVal - maxQValue) < 0.001 {
                    bestActions.append(action)
                }
            }
            
            return bestActions.randomElement() ?? Int.random(in: 0..<numActions)
        }
    }
    
    /// Updates the Q-Value using the Q-learning formula
    func updateQValue(state: Int, action: Int, reward: Double, nextState: Int) {
        let currentQ = getQValue(state: state, action: action)
        
        var maxNextQ = -Double.greatestFiniteMagnitude
        for nextAction in 0..<numActions {
            let nextQ = getQValue(state: nextState, action: nextAction)
            if nextQ > maxNextQ {
                maxNextQ = nextQ
            }
        }
        
        let newQ = currentQ + alpha * (reward + gamma * maxNextQ - currentQ)
        setQValue(state: state, action: action, value: newQ)
        
        saveQTable()
    }
    
    /// Applies an immediate reward for the most recent state and action
    func applyReward(_ reward: Double, state: Int?, action: Int?) {
        guard let s = state, let a = action else { return }
        
        let currentQ = getQValue(state: s, action: a)
        // Simplified Q-learning update for immediate reward without next state maxQ
        let newQ = currentQ + alpha * (reward - currentQ)
        setQValue(state: s, action: a, value: newQ)
        
        print("QLearningManager: Updated Q-Value for [\(s)] -> \(a): \(newQ)")
        saveQTable()
    }
    
    private var fileURL: URL {
        let sourceFileURL = URL(fileURLWithPath: #file)
        let projectDir = sourceFileURL.deletingLastPathComponent().deletingLastPathComponent()
        return projectDir.appendingPathComponent("spatial_qtable.json")
    }

    private func saveQTable() {
        do {
            let data = try JSONEncoder().encode(qTable)
            try data.write(to: fileURL)
            UserDefaults.standard.set(qTable, forKey: userDefaultsKey)
        } catch {
            print("Failed to save Spatial Q-Table: \(error)")
        }
    }
    
    private func loadQTable() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                qTable = try JSONDecoder().decode([String: Double].self, from: data)
                print("QLearningManager: Loaded from JSON.")
            } else if let savedTable = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double] {
                qTable = savedTable
                print("QLearningManager: Loaded from UserDefaults backup.")
            }
        } catch {
            print("Failed to load Spatial Q-Table: \(error)")
        }
    }
}
