import Foundation
import GameplayKit

// Keep the enums for the scene to map easily to animations/eyes
enum PetAction {
    case idle, wander, followCursor, sleep, jump, sit, spin, sulk, dizzy, tickled
    case peekWindow, sitOnTaskbar, investigate
}

enum PetEmotion {
    case normal, happy, sad, angry, sleepy, love, shock, thinking, dizzy, bored, excited, curious
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
    private var aiTimer: TimeInterval = 60.0 // Start high so it queries immediately on boot
    
    override func didEnter(from previousState: GKState?) {
        brain.currentAction = .idle
        brain.currentEmotion = .normal
        idleTime = 0
        // We do NOT reset aiTimer here, so it resumes its 60s cooldown across states
        brain.agent.behavior = nil // Stop moving
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        idleTime += seconds
        aiTimer += seconds
        
        // Every 60 seconds, ask the AI what to do (to save API limits)
        if aiTimer > 60.0 {
            aiTimer = 0
            brain.queryAI()
        }
    }
}

class PetWanderState: PetBaseState {
    private var wanderTime: TimeInterval = 0
    private var maxWanderTime: TimeInterval = 0
    private var targetPoint: vector_float2?
    private var targetAction: PetAction?
    
    override func didEnter(from previousState: GKState?) {
        brain.currentEmotion = .normal
        wanderTime = 0
        maxWanderTime = TimeInterval.random(in: 5...15)
        
        let behavior = GKBehavior()
        let envManager = DesktopEnvironmentManager.shared
        
        targetAction = brain.currentAction // Use what the AI (or init) decided!
        if targetAction == .idle { targetAction = .wander } // Fallback for init
        
        if targetAction == .peekWindow || targetAction == .investigate, let window = envManager.visibleElements.first(where: { $0.type == .window }) {
            // Target a window
            let screenW = NSScreen.main?.frame.width ?? 800
            let screenH = NSScreen.main?.frame.height ?? 600
            let worldX = Float(((window.frame.minX / screenW) - 0.5) * 30.0)
            let worldY = Float((((screenH - window.frame.midY) / screenH) - 0.5) * 20.0)
            targetPoint = vector_float2(x: worldX, y: worldY)
        } 
        else if targetAction == .sitOnTaskbar, let taskbar = envManager.visibleElements.first(where: { $0.type == .taskbar }) {
            // Target taskbar
            let screenH = NSScreen.main?.frame.height ?? 600
            let worldX = brain.agent.position.x // Go straight down
            let dockRatioY = ((screenH - taskbar.frame.minY) / screenH) - 0.5
            let worldY = Float(dockRatioY * 20.0) + 1.0
            targetPoint = vector_float2(x: worldX, y: worldY)
        } 
        else {
            // Default Wander: Pick a random point far left or far right to walk across the screen HORIZONTALLY
            let isLeft = Bool.random()
            let worldX = isLeft ? Float.random(in: -15.0 ... -5.0) : Float.random(in: 5.0 ... 15.0)
            let worldY = brain.agent.position.y // Keep the exact same height so it walks purely left/right!
            targetPoint = vector_float2(x: worldX, y: worldY)
            targetAction = .wander
        }
        
        brain.currentAction = targetAction!
        
        if let target = targetPoint {
            let targetAgent = GKAgent2D()
            targetAgent.position = target
            behavior.setWeight(1.0, for: GKGoal(toSeekAgent: targetAgent))
        }
        
        behavior.setWeight(0.5, for: GKGoal(toReachTargetSpeed: 1.0))
        
        // Add obstacle avoidance for windows
        var obstacles: [GKPolygonObstacle] = []
        for element in envManager.visibleElements where element.type == .window {
            let screenW = NSScreen.main?.frame.width ?? 800
            let screenH = NSScreen.main?.frame.height ?? 600
            
            let minX = Float(((element.frame.minX / screenW) - 0.5) * 30.0)
            let maxX = Float(((element.frame.maxX / screenW) - 0.5) * 30.0)
            let minY = Float((((screenH - element.frame.maxY) / screenH) - 0.5) * 20.0)
            let maxY = Float((((screenH - element.frame.minY) / screenH) - 0.5) * 20.0)
            
            let p1 = vector_float2(minX, minY)
            let p2 = vector_float2(maxX, minY)
            let p3 = vector_float2(maxX, maxY)
            let p4 = vector_float2(minX, maxY)
            obstacles.append(GKPolygonObstacle(points: [p1, p2, p3, p4]))
        }
        if !obstacles.isEmpty {
            behavior.setWeight(1.5, for: GKGoal(toAvoid: obstacles, maxPredictionTime: 1.0))
        }
        
        brain.agent.behavior = behavior
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        wanderTime += seconds
        brain.energy = max(0, brain.energy - (1.0 * seconds)) // Burn energy walking
        
        if let target = targetPoint {
            let dist = distance(brain.agent.position, target)
            if dist < 2.0 {
                // Reached target
                if let action = targetAction {
                    brain.currentAction = action
                    brain.currentEmotion = .curious
                }
                stateMachine?.enter(PetIdleState.self)
                return
            }
        }
        
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
    
    private var lastTickTime: TimeInterval = 0
    private var isQueryingAI = false
    
    init() {
        stateMachine.enter(PetWanderState.self)
    }
    
    func queryAI() {
        guard !isQueryingAI else { return }
        isQueryingAI = true
        
        let envManager = DesktopEnvironmentManager.shared
        var context = "Visible Windows: "
        for el in envManager.visibleElements where el.type == .window {
            context += "\(el.title), "
        }
        if envManager.visibleElements.contains(where: { $0.type == .taskbar }) {
            context += "Taskbar/Dock is visible. "
        }
        context += "Current Energy: \(Int(energy)). Current Emotion: \(currentEmotion)."
        
        AIEngine.shared.decideNextMove(context: context) { [weak self] decision in
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
        case "sleepy": currentEmotion = .sleepy
        case "excited": currentEmotion = .excited
        case "curious": currentEmotion = .curious
        case "bored": currentEmotion = .bored
        case "thinking": currentEmotion = .thinking
        default: currentEmotion = .normal
        }
        
        switch decision.action.lowercased() {
        case "wander": stateMachine.enter(PetWanderState.self)
        case "peekwindow":
            currentAction = .peekWindow
            stateMachine.enter(PetWanderState.self) // Let wander handle pathing
        case "sitontaskbar":
            currentAction = .sitOnTaskbar
            stateMachine.enter(PetWanderState.self)
        case "sleep": stateMachine.enter(PetSleepState.self)
        case "jump": currentAction = .jump
        case "spin": currentAction = .spin
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
