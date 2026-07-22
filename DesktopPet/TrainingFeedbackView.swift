import SwiftUI

class TrainingViewModel: ObservableObject {
    @Published var currentActionName: String = "Idle"
    private var timer: Timer?
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
        ReinforcementLearningModel.shared.applyReward(1.0)
        QLearningManager.shared.applyReward(1.0, state: brain.lastQState, action: brain.lastQAction)
    }

    func giveBadFeedback() {
        guard let brain = getBrain?() else { return }
        ReinforcementLearningModel.shared.applyReward(-1.0)
        QLearningManager.shared.applyReward(-1.0, state: brain.lastQState, action: brain.lastQAction)
    }
}

struct TrainingFeedbackView: View {
    @StateObject private var viewModel = TrainingViewModel()
    var getBrain: () -> PetBrain?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("RL Training Mode")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text("Action: \(viewModel.currentActionName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            HStack(spacing: 12) {
                Button(action: { viewModel.giveGoodFeedback() }) {
                    HStack(spacing: 4) {
                        Text("👍")
                            .font(.system(size: 14))
                        Text("Good")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.3))
                    .foregroundColor(.green)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { viewModel.giveBadFeedback() }) {
                    HStack(spacing: 4) {
                        Text("👎")
                            .font(.system(size: 14))
                        Text("Bad")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.3))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(12)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                Color.black.opacity(0.5)
            }
        )
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .onAppear {
            viewModel.getBrain = getBrain
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}
