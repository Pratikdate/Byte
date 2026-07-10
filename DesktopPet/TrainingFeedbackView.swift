import SwiftUI

class TrainingViewModel: ObservableObject {
    @Published var currentActionName: String = "Idle"
    
    // Timer to poll PetBrain state (since it's not ObservableObject)
    private var timer: Timer?
    
    // We pass a reference to PetBrain
    var getBrain: (() -> PetBrain?)?
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let brain = self.getBrain?() else { return }
            let newAction = brain.currentAction.rawValue.capitalized
            if self.currentActionName != newAction {
                self.currentActionName = newAction
            }
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    func giveGoodFeedback() {
        guard let brain = getBrain?() else { return }
        // Give +1.0 to ReinforcementLearningModel
        ReinforcementLearningModel.shared.applyReward(1.0)
        // Give +1.0 to QLearningManager if a wander just happened
        QLearningManager.shared.applyReward(1.0, state: brain.lastQState, action: brain.lastQAction)
    }
    
    func giveBadFeedback() {
        guard let brain = getBrain?() else { return }
        // Give -1.0 to ReinforcementLearningModel
        ReinforcementLearningModel.shared.applyReward(-1.0)
        // Give -1.0 to QLearningManager if a wander just happened
        QLearningManager.shared.applyReward(-1.0, state: brain.lastQState, action: brain.lastQAction)
    }
}

struct TrainingFeedbackView: View {
    @StateObject private var viewModel = TrainingViewModel()
    var getBrain: () -> PetBrain?
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Training Mode Active")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Action: \(viewModel.currentActionName)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            HStack(spacing: 16) {
                Button(action: {
                    viewModel.giveGoodFeedback()
                }) {
                    VStack {
                        Text("👍")
                            .font(.system(size: 24))
                        Text("Good")
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.7))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    viewModel.giveBadFeedback()
                }) {
                    VStack {
                        Text("👎")
                            .font(.system(size: 24))
                        Text("Bad")
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.7))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .onAppear {
            viewModel.getBrain = getBrain
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}
