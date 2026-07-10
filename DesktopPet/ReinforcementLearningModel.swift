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
        
        // Standard Q-learning formula (simplified for single-step immediate rewards)
        // Q(s,a) = Q(s,a) + alpha * (reward - Q(s,a))
        let newQ = currentQ + learningRate * (reward - currentQ)
        
        qTable[state]?[actionStr] = newQ
        print("ReinforcementLearningModel: Updated Q-Value for [\(state.timeOfDay), \(state.attentionState)] -> \(actionStr): \(newQ)")
        
        saveModel()
    }
    
    // MARK: - Persistence
    
    private func saveModel() {
        do {
            let data = try JSONEncoder().encode(qTable)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            print("Failed to save Q-Table: \(error)")
        }
    }
    
    private func loadModel() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        do {
            qTable = try JSONDecoder().decode([RLState: [String: Double]].self, from: data)
            print("ReinforcementLearningModel: Loaded Q-Table successfully.")
        } catch {
            print("Failed to load Q-Table: \(error)")
        }
    }
}
