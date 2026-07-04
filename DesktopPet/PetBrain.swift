import Foundation
import GameplayKit

// Keep the enums for the scene to map easily to animations/eyes
enum PetAction {
    case idle, wander, followCursor, sleep, jump, sit, spin, sulk, dizzy, tickled
    case peekWindow, sitOnTaskbar, investigate
    case stepBack, dance, bow, stretch, roll, hide
}

enum PetEmotion {
    case normal, happy, sad, angry, sleepy, love, shock, thinking, dizzy, bored, excited, curious, embarrassed
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
    private var idleTime: TimeInterval = 0
    private var aiTimer: TimeInterval = 20.0 // Start high so it queries immediately on boot
    private var nextWanderTime: TimeInterval = 0
    
    override func didEnter(from previousState: GKState?) {
        brain.currentAction = .idle
        brain.currentEmotion = .normal
        idleTime = 0
        // Very short pause before wandering again — 1 to 3 seconds max
        nextWanderTime = TimeInterval.random(in: 1.0...3.0)
        brain.agent.behavior = nil // Stop moving
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        idleTime += seconds
        aiTimer += seconds
        
        // Every 25 seconds, ask the AI what to do (free local inference!)
        if aiTimer > 25.0 {
            aiTimer = 0
            brain.queryAI()
        } else if idleTime > nextWanderTime {
            // Autonomously wander — always active, always exploring!
            brain.currentAction = .wander
            stateMachine?.enter(PetWanderState.self)
        }
    }
}

class PetWanderState: PetBaseState {
    private var wanderTime: TimeInterval = 0
    private var maxWanderTime: TimeInterval = 0
    private var targetX: CGFloat = 0
    private var targetY: CGFloat = 0
    
    override func didEnter(from previousState: GKState?) {
        brain.currentEmotion = .normal
        wanderTime = 0
        maxWanderTime = TimeInterval.random(in: 8...18) // Walk for a good while
        brain.agent.behavior = nil
        
        // Pick a random X within visible screen bounds (camera shows ±6 world units)
        let currentX = CGFloat(brain.agent.position.x)
        let goRight = currentX <= 0
        targetX = goRight ? CGFloat.random(in: 2.0...5.5) : CGFloat.random(in: -5.5...(-2.0))
        
        // Pick a random Y within visible screen bounds (Y goes from -2.8 to 4.5)
        targetY = CGFloat.random(in: -2.5...4.5)
        
        brain.currentAction = .wander
        
        // Tell the scene to start the step-based walk animation
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
        if brain.energy > 80 {
            stateMachine?.enter(PetIdleState.self)
        }
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
    
    init() {
        stateMachine.enter(PetIdleState.self) // Start idle — let AI decide what to do first
    }
    
    func queryAI(userMessage: String? = nil) {
        guard !isQueryingAI else { return }
        isQueryingAI = true
        
        let envManager = DesktopEnvironmentManager.shared
        
        // Get the frontmost app name via Accessibility API
        var frontApp = "Desktop"
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            frontApp = frontmostApp.localizedName ?? "Desktop"
        }
        
        var windowList: [String] = []
        for el in envManager.visibleElements where el.type == .window {
            if let title = el.title, !title.isEmpty { windowList.append(title) }
        }
        let hasDock = envManager.visibleElements.contains(where: { $0.type == .taskbar })
        
        var context = "Active app: \(frontApp)."
        if !windowList.isEmpty {
            context += " Open windows: \(windowList.prefix(3).joined(separator: ", "))."
        }
        if hasDock { context += " Dock is visible." }
        context += " Energy: \(Int(energy)). Mood: \(currentEmotion)."
        
        AIEngine.shared.decideNextMove(context: context, userMessage: userMessage) { [weak self] decision in
            DispatchQueue.main.async {
                self?.isQueryingAI = false
                guard let self = self, let decision = decision else { return }
                
                self.applyDecision(decision)
            }
        }
    }
    
    private func applyDecision(_ decision: AIPetDecision) {
        if let thought = decision.thought as String?, !thought.isEmpty {
            self.onThoughtGenerated?(thought)
        }
        
        // Map strings to Enums
        switch decision.emotion.lowercased() {
        case "happy": currentEmotion = .happy
        case "sad": currentEmotion = .sad
        case "angry": currentEmotion = .angry
        case "sleepy": currentEmotion = .sleepy
        case "excited": currentEmotion = .excited
        case "curious": currentEmotion = .curious
        case "bored": currentEmotion = .bored
        case "thinking": currentEmotion = .thinking
        case "love": currentEmotion = .love
        case "shock": currentEmotion = .shock
        case "embarrassed": currentEmotion = .embarrassed
        default: currentEmotion = .normal
        }
        
        switch decision.action.lowercased() {
        case "wander": stateMachine.enter(PetWanderState.self)
        case "peekwindow":
            currentAction = .peekWindow
            stateMachine.enter(PetWanderState.self)
        case "sitontaskbar":
            currentAction = .sitOnTaskbar
            stateMachine.enter(PetWanderState.self)
        case "sleep": stateMachine.enter(PetSleepState.self)
        case "jump": currentAction = .jump
        case "spin": currentAction = .spin
        case "stepback": currentAction = .stepBack
        case "dance": currentAction = .dance
        case "bow": currentAction = .bow
        case "stretch": currentAction = .stretch
        case "roll": currentAction = .roll
        case "hide": currentAction = .hide
        case "idle": stateMachine.enter(PetIdleState.self)
        default: break
        }
    }
    
    func tick(currentTime: TimeInterval, cursorMoved: Bool) -> (action: PetAction, emotion: PetEmotion, changed: Bool) {
        let dt = lastTickTime == 0 ? 0.016 : currentTime - lastTickTime
        lastTickTime = currentTime
        
        let oldAction = currentAction
        let oldEmotion = currentEmotion
        
        stateMachine.update(deltaTime: dt)
        agent.update(deltaTime: dt)
        
        let changed = (oldAction != currentAction) || (oldEmotion != currentEmotion)
        return (currentAction, currentEmotion, changed)
    }
    
    // External Triggers
    func triggerDizzy() {
        stateMachine.enter(PetInteractState.self)
        currentAction = .dizzy
        currentEmotion = .dizzy
    }
    
    func triggerTickle() {
        stateMachine.enter(PetInteractState.self)
        currentAction = .tickled
        currentEmotion = .happy
    }
    
    func triggerStartle() {
        stateMachine.enter(PetInteractState.self)
        currentAction = .jump
        currentEmotion = .shock
    }
    
    func setDragged(_ dragged: Bool) {
        isBeingDragged = dragged
        if dragged {
            stateMachine.enter(PetInteractState.self)
            currentAction = .sulk
            currentEmotion = .angry
        } else {
            stateMachine.enter(PetIdleState.self)
        }
    }
}
