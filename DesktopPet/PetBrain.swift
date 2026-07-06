import Foundation
import GameplayKit
import CoreGraphics

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
                    nextActionTime = TimeInterval.random(in: 20.0...40.0)
                case .idle:
                    nextActionTime = TimeInterval.random(in: 10.0...20.0)
                default:
                    nextActionTime = TimeInterval.random(in: 4.0...10.0)
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
    
    // Routine Phase (Spec §7)
    var currentRoutinePhase: PetRoutinePhase = .current()
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
        // Routine phase biases
        let phase = currentRoutinePhase
        let isNightTime = (phase == .night || phase == .lateNight)
        let isEarlyMorning = (phase == .earlyMorning)
        
        // Priority order from spec: Startled > Annoyed > Sleepy/Asleep > Curious > Excited > Lonely > Bored > Content
        if annoyance > 80 { return .angry }
        if energy < 15 || (isNightTime && energy < 40) { return .sleepy }
        if isEarlyMorning && energy < 50 { return .sleepy }
        if curiosity > 80 { return .curious }
        if mood > 85 && energy > 70 { return .proud }
        if mood > 70 && curiosity > 60 { return .happy }
        if mood < 30 { return .sad }
        if curiosity < 20 && !isNightTime { return .bored }
        if isNightTime { return .sleepy }
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
        
        var weights: [PetAction: Double] = [
            .idle: 30.0,
            .wander: 25.0,
            .sleep: 8.0,
            .jump: 5.0,
            .sit: 8.0,
            .spin: 4.0,
            // New interactive actions
            .sitOnCorner: 4.0,
            .sitOnMenuBar: 3.0,
            .climbWindow: 4.0,
            .pushWidget: 3.0,
            .tapWindow: 3.0,
            .sneeze: 1.0,
            .backflip: 2.0,
            .headbang: 2.0,
            .wave: 3.0,
            .trip: 0.5
        ]
        
        if effectiveMode == .work {
            // Work mode: prefer quiet, stay out of the way
            weights = [
                .idle: 45.0,
                .wander: 8.0,
                .sleep: 20.0,
                .sit: 15.0,
                .jump: 0.0,
                .spin: 0.0,
                .sitOnCorner: 8.0,
                .sitOnMenuBar: 4.0,
                .wave: 1.0
            ]
        } else if effectiveMode == .play {
            // Play mode: active and wandering
            weights[.wander] = 40.0
            weights[.jump] = 15.0
            weights[.spin] = 8.0
            weights[.sleep] = 0.0
            weights[.idle] = 15.0
            weights[.backflip] = 8.0
            weights[.headbang] = 6.0
            weights[.climbWindow] = 8.0
            weights[.pushWidget] = 6.0
            weights[.tapWindow] = 6.0
            weights[.sitOnMenuBar] = 5.0
            weights[.wave] = 5.0
            weights[.trip] = 2.0
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
