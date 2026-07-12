import Foundation

struct RLState: Hashable, Codable {
    let timeOfDay: String
    let attentionState: String
    let hasActiveWindows: Bool
}

class ReinforcementLearningModel {
    static let shared = ReinforcementLearningModel()
    
    // Q-Table: [State : [Action : QValue]]
    private var qTable: [RLState: [String: Double]] = [:]
    
    // Learning parameters
    private let learningRate: Double = 0.1
    private let discountFactor: Double = 0.9
    private var epsilon: Double = 0.2 // 20% exploration
    
    private let saveKey = "ByteQTable"
    
    // The most recent state-action pair to apply rewards to
    private var lastState: RLState?
    private var lastAction: PetAction?
    
    // Baseline actions to explore
    private let availableActions: [PetAction] = [
        .idle, .wander, .sleep, .sit, .jump, .spin, 
        .sitOnCorner, .sitOnMenuBar, .climbWindow, 
        .wave, .backflip, .headbang, .sneeze, .tapWindow, .pushWidget
    ]
    
    private init() {
        loadModel()
    }
    
    func getCurrentState() -> RLState {
        let attention = InteractionDirector.shared.currentAttention()
        let attentionStr = String(describing: attention)
        
        let timeOfDay = PetRoutinePhase.current().rawValue
        
        let elements = DesktopEnvironmentManager.shared.visibleElements
        let hasActiveWindows = !elements.filter({ $0.type == .window }).isEmpty
        
        return RLState(timeOfDay: timeOfDay, attentionState: attentionStr, hasActiveWindows: hasActiveWindows)
    }
    
    func chooseAction(state: RLState, isWorkMode: Bool, isMuted: Bool) -> PetAction {
        // If the user has explicitly requested silence, force a quiet action (override ML)
        let secondsSinceSpoke = DialogueContextTracker.shared.secondsSinceInteraction()
        if secondsSinceSpoke > 300 {
            lastState = state
            lastAction = .sleep
            return .sleep
        }
        
        // Epsilon-greedy selection
        var action: PetAction
        if Double.random(in: 0...1) < epsilon {
            // Explore
            action = availableActions.randomElement() ?? .idle
        } else {
            // Exploit best known action
            action = getBestAction(for: state)
        }
        
        // Filter out noisy actions if in work mode
        if isWorkMode && isNoisy(action) {
            action = .sitOnCorner // Safe fallback
        }
        
        lastState = state
        lastAction = action
        return action
    }
    
    private func getBestAction(for state: RLState) -> PetAction {
        guard let stateActions = qTable[state], !stateActions.isEmpty else {
            return availableActions.randomElement() ?? .idle
        }
        
        let best = stateActions.max { a, b in a.value < b.value }
        if let bestActionName = best?.key, let bestAction = PetAction(rawValue: bestActionName) {
            return bestAction
        }
        return .idle
    }
    
    private func isNoisy(_ action: PetAction) -> Bool {
        return [.jump, .spin, .dance, .backflip, .headbang, .sneeze, .tapWindow, .pushWidget].contains(action)
    }
    
    func applyReward(_ reward: Double) {
        guard let state = lastState, let action = lastAction else { return }
        let actionStr = action.rawValue
        
        if qTable[state] == nil {
            qTable[state] = [:]
        }
        
        let currentQ = qTable[state]?[actionStr] ?? 0.0
        
        let nextState = getCurrentState()
        let nextStateActions = qTable[nextState] ?? [:]
        let maxNextQ = nextStateActions.values.max() ?? 0.0
        
        // Full Bellman Equation considering future rewards
        let newQ = currentQ + learningRate * (reward + discountFactor * maxNextQ - currentQ)
        
        qTable[state]?[actionStr] = newQ
        print("ReinforcementLearningModel: Updated Q-Value for [\(state.timeOfDay), \(state.attentionState)] -> \(actionStr): \(newQ)")
        
        saveModel()
    }
    
    // MARK: - Persistence
    
    private var fileURL: URL {
        let sourceFileURL = URL(fileURLWithPath: #file)
        let projectDir = sourceFileURL.deletingLastPathComponent().deletingLastPathComponent()
        return projectDir.appendingPathComponent("rl_qtable.json")
    }
    
    private func saveModel() {
        do {
            let data = try JSONEncoder().encode(qTable)
            try data.write(to: fileURL)
            // Still save to UserDefaults as a backup
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            print("Failed to save Q-Table: \(error)")
        }
    }
    
    private func loadModel() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                qTable = try JSONDecoder().decode([RLState: [String: Double]].self, from: data)
                print("ReinforcementLearningModel: Loaded Q-Table from JSON.")
            } else if let data = UserDefaults.standard.data(forKey: saveKey) {
                qTable = try JSONDecoder().decode([RLState: [String: Double]].self, from: data)
                print("ReinforcementLearningModel: Loaded Q-Table from UserDefaults backup.")
            }
        } catch {
            print("Failed to load Q-Table: \(error)")
        }
    }
}
