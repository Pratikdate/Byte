import SwiftUI

struct ThoughtBubbleView: View {
    let thoughtText: String
    let emotion: String
    @State private var isVisible: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(emotionEmoji(emotion))
                .font(.system(size: 16))
            
            Text(thoughtText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                Color.black.opacity(0.4)
                LinearGradient(colors: [Color.cyan.opacity(0.15), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
    
    private func emotionEmoji(_ emotion: String) -> String {
        switch emotion.lowercased() {
        case "happy": return "😊"
        case "sad": return "😢"
        case "curious": return "🧐"
        case "excited": return "🤩"
        case "sleepy": return "😴"
        case "thinking": return "💡"
        default: return "🐾"
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
