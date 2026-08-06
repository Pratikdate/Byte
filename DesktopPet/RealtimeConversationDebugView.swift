import SwiftUI
import AppKit

// MARK: - Debug Log Data Models

struct LogItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let speaker: String // "User" or "Byte (gemma:2b)"
    var text: String
    var action: String?
    var emotion: String?
    var systemPrompt: String?
    var isStreaming: Bool = false
    var rating: Rating = .none

    enum Rating: String, Codable {
        case none = "None"
        case good = "Good"
        case bad = "Needs Fine-Tuning"
    }
}

// MARK: - Realtime Conversation Logger

class RealtimeConversationLogger: ObservableObject {
    static let shared = RealtimeConversationLogger()

    @Published var logs: [LogItem] = []
    @Published var isModelGenerating: Bool = false
    @Published var isListeningForSpeech: Bool = false
    @Published var liveTranscript: String = ""
    @Published var currentAction: String = "idle"
    @Published var currentEmotion: String = "normal"
    @Published var totalGood: Int = 0
    @Published var totalBad: Int = 0

    private init() {}

    func setListeningState(_ listening: Bool) {
        DispatchQueue.main.async {
            self.isListeningForSpeech = listening
            if !listening {
                self.liveTranscript = ""
            }
        }
    }

    func updateLiveTranscript(_ text: String) {
        DispatchQueue.main.async {
            self.liveTranscript = text
        }
    }

    func logUserMessage(_ text: String) {
        DispatchQueue.main.async {
            self.isListeningForSpeech = false
            self.liveTranscript = ""
            let item = LogItem(
                timestamp: Date(),
                speaker: "User (Apple System STT)",
                text: text,
                action: nil,
                emotion: nil,
                systemPrompt: nil,
                isStreaming: false
            )
            self.logs.append(item)
        }
    }

    func startModelTurn(systemPrompt: String, userMessage: String?) {
        DispatchQueue.main.async {
            self.isModelGenerating = true
            let item = LogItem(
                timestamp: Date(),
                speaker: "Byte (byte-llm)",
                text: "",
                action: "thinking...",
                emotion: "curious",
                systemPrompt: systemPrompt,
                isStreaming: true
            )
            self.logs.append(item)
        }
    }

    func updateActionAndEmotion(action: String, emotion: String) {
        DispatchQueue.main.async {
            self.currentAction = action
            self.currentEmotion = emotion
            if let lastIndex = self.logs.indices.last, self.logs[lastIndex].speaker.contains("Byte") {
                self.logs[lastIndex].action = action
                self.logs[lastIndex].emotion = emotion
            }
        }
    }

    func appendStreamSentence(_ sentence: String) {
        DispatchQueue.main.async {
            if let lastIndex = self.logs.indices.last, self.logs[lastIndex].speaker.contains("Byte") {
                if self.logs[lastIndex].text.isEmpty {
                    self.logs[lastIndex].text = sentence
                } else {
                    self.logs[lastIndex].text += " " + sentence
                }
            }
        }
    }

    func completeModelTurn() {
        DispatchQueue.main.async {
            self.isModelGenerating = false
            if let lastIndex = self.logs.indices.last, self.logs[lastIndex].speaker.contains("Byte") {
                self.logs[lastIndex].isStreaming = false
            }
        }
    }

    func setRating(for itemID: UUID, rating: LogItem.Rating) {
        if let idx = logs.firstIndex(where: { $0.id == itemID }) {
            let old = logs[idx].rating
            if old == .good { totalGood -= 1 }
            if old == .bad { totalBad -= 1 }

            logs[idx].rating = rating
            if rating == .good { totalGood += 1 }
            if rating == .bad { totalBad += 1 }

            // Export to fine-tune dataset file automatically
            saveToFineTuneDataset(item: logs[idx])
        }
    }

    func clearLogs() {
        logs.removeAll()
        totalGood = 0
        totalBad = 0
    }

    private func saveToFineTuneDataset(item: LogItem) {
        guard let prompt = item.systemPrompt else { return }

        let datasetPath = NSHomeDirectory() + "/Documents/Byte/training/finetune_dataset.jsonl"
        let entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
            "prompt": prompt,
            "response": "[ACTION: \(item.action ?? "idle")] [EMOTION: \(item.emotion ?? "normal")] \(item.text)",
            "rating": item.rating.rawValue
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: entry),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let line = jsonString + "\n"
            if let handle = FileHandle(forWritingAtPath: datasetPath) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try? line.write(toFile: datasetPath, atomically: true, encoding: .utf8)
            }
            print("[DebugHUD] Saved fine-tune dataset entry to \(datasetPath)")
        }
    }
}

// MARK: - SwiftUI Debug HUD View

struct RealtimeConversationDebugView: View {
    @StateObject private var logger = RealtimeConversationLogger.shared
    @State private var expandedPromptID: UUID? = nil
    @State private var selectedTab: Int = 0

    private var timeFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(logger.isListeningForSpeech ? Color.red : (logger.isModelGenerating ? Color.yellow : Color.green))
                        .frame(width: 10, height: 10)
                        .shadow(color: logger.isListeningForSpeech ? .red : (logger.isModelGenerating ? .yellow : .green), radius: 4)

                    Text("⚡ Byte Debugger & Memory Graph")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                Picker("", selection: $selectedTab) {
                    Text("💬 Live Feed").tag(0)
                    Text("🧠 Memory Graph").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 210)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { logger.clearLogs() }) {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(logger.isListeningForSpeech ? Color.red.opacity(0.2) : Color.black.opacity(0.4))

            Divider().background(Color.white.opacity(0.1))

            Group {
                if selectedTab == 0 {
                    // Tab 0: Live Feed
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if logger.logs.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "bubble.left.and.bubble.right")
                                            .font(.system(size: 28))
                                            .foregroundColor(.white.opacity(0.3))
                                        Text("No conversation events logged yet.")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.4))
                                        Text("Speak to Byte using Cmd long-press or click to see real-time model output.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.3))
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding(.vertical, 40)
                                } else {
                                    ForEach(logger.logs) { item in
                                        LogItemRow(item: item, expandedPromptID: $expandedPromptID, onRate: { rating in
                                            logger.setRating(for: item.id, rating: rating)
                                        })
                                        .id(item.id)
                                    }
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: logger.logs.count) { _ in
                            if let lastID = logger.logs.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                    }
                } else {
                    // Tab 1: Memory Graph View
                    MemoryGraphView()
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Footer Bar: Fine-Tuning Stats & Evaluator
            HStack {
                HStack(spacing: 12) {
                    Text("Evaluations:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 4) {
                        Text("👍 Good:")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("\(logger.totalGood)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    }

                    HStack(spacing: 4) {
                        Text("👎 Needs Fine-Tuning:")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        Text("\(logger.totalBad)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                Text("Dataset: training/finetune_dataset.jsonl")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
        }
        .frame(width: 480, height: 380)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                Color.black.opacity(0.65)
            }
        )
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Single Log Row Component

struct LogItemRow: View {
    let item: LogItem
    @Binding var expandedPromptID: UUID?
    let onRate: (LogItem.Rating) -> Void

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: item.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Speaker Badge
                HStack(spacing: 4) {
                    Image(systemName: item.speaker.contains("User") ? "person.circle.fill" : "cpu.fill")
                        .font(.system(size: 11))
                    Text(item.speaker)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(item.speaker.contains("User") ? .cyan : .purple)

                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                if item.isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }

                // Action & Emotion Tags (if Byte)
                if let act = item.action, let emo = item.emotion {
                    HStack(spacing: 4) {
                        Text("[ACT: \(act)]")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.25))
                            .foregroundColor(.blue)
                            .cornerRadius(4)

                        Text("[EMO: \(emo)]")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.25))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }

            // Message Text
            Text(item.text.isEmpty ? "(Waiting for model stream...)" : item.text)
                .font(.system(size: 12))
                .foregroundColor(item.text.isEmpty ? .white.opacity(0.4) : .white)
                .lineSpacing(2)

            // Debug Expansion & Rating (for Byte turns)
            if item.speaker.contains("Byte") {
                HStack(spacing: 12) {
                    if item.systemPrompt != nil {
                        Button(action: {
                            if expandedPromptID == item.id {
                                expandedPromptID = nil
                            } else {
                                expandedPromptID = item.id
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: expandedPromptID == item.id ? "chevron.up" : "doc.text.magnifyingglass")
                                Text(expandedPromptID == item.id ? "Hide Prompt" : "Inspect System Prompt")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Rating Buttons for Fine-Tuning
                    HStack(spacing: 6) {
                        Text("Fine-Tune Rating:")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))

                        Button(action: { onRate(.good) }) {
                            Text("👍 Good")
                                .font(.system(size: 10, weight: item.rating == .good ? .bold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.rating == .good ? Color.green.opacity(0.4) : Color.white.opacity(0.08))
                                .foregroundColor(item.rating == .good ? .green : .white.opacity(0.7))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        Button(action: { onRate(.bad) }) {
                            Text("👎 Poor")
                                .font(.system(size: 10, weight: item.rating == .bad ? .bold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.rating == .bad ? Color.red.opacity(0.4) : Color.white.opacity(0.08))
                                .foregroundColor(item.rating == .bad ? .red : .white.opacity(0.7))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)

                // Expanded System Prompt Box
                if expandedPromptID == item.id, let prompt = item.systemPrompt {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FULL SYSTEM PROMPT SENT TO GEMMA 2B:")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.yellow.opacity(0.8))

                        ScrollView {
                            Text(prompt)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.speaker.contains("User") ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.speaker.contains("User") ? Color.blue.opacity(0.25) : Color.purple.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Memory Graph Tab View

struct MemoryGraphView: View {
    @State private var userFacts: String = MemoryGraph.shared.getUserFactsString()
    @State private var behavioralRules: String = MemoryGraph.shared.getBehavioralRulesString()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section 1: User Facts & Learned Preferences
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.cyan)
                        Text("Learned User Facts & Preferences")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.cyan)
                    }

                    Text(userFacts)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                }

                // Section 2: Behavioral Rules
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "shield.checklist")
                            .foregroundColor(.orange)
                        Text("Behavioral System Rules (Must Follow)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                    }

                    Text(behavioralRules)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                }

                // Section 3: Web Visualizer Quick Link
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Graph Visualizer")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                        Text("Open MemoryVisualizer.html to render interactive node graph")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    Button(action: {
                        let htmlPath = NSHomeDirectory() + "/Documents/Byte/MemoryVisualizer.html"
                        NSWorkspace.shared.open(URL(fileURLWithPath: htmlPath))
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                            Text("Open Visualizer")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.3))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            }
            .padding(12)
        }
        .onAppear {
            userFacts = MemoryGraph.shared.getUserFactsString()
            behavioralRules = MemoryGraph.shared.getBehavioralRulesString()
        }
    }
}
