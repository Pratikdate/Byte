import SwiftUI

struct ByteSettingsView: View {
    @State private var selectedTab = 0
    @State private var isMuted: Bool = false
    @State private var petMode: String = "Auto"
    @State private var useCloudAI: Bool = false
    @State private var focusEngineStatus: String = "Active"
    @State private var activePersonality: PersonalityProfile = SettingsManager.shared.activePersonality
    @State private var activeTheme: ByteTheme = SettingsManager.shared.activeTheme
    
    @State private var memoriesList: [String] = []
    @State private var behavioralRules: [String] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar (Light Mode with 🐾 Logo)
            HStack(spacing: 12) {
                Text("🐾")
                    .font(.system(size: 28))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Byte Control Center")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                    Text("Autonomous Developer Companion")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white)
            
            Divider()
                .background(Color(red: 0.88, green: 0.91, blue: 0.94))
            
            // Custom Tab Bar (Light Mode)
            HStack(spacing: 16) {
                TabButton(title: "Companion", icon: "person.circle.fill", index: 0, selectedTab: $selectedTab)
                TabButton(title: "Developer Focus", icon: "brain.head.profile", index: 1, selectedTab: $selectedTab)
                TabButton(title: "AI Engine", icon: "cpu.fill", index: 2, selectedTab: $selectedTab)
                TabButton(title: "Memory Graph", icon: "externaldrive.connected.to.line.below.fill", index: 3, selectedTab: $selectedTab)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
            
            Divider()
                .background(Color(red: 0.88, green: 0.91, blue: 0.94))
            
            // Content Area
            ScrollView {
                VStack(spacing: 16) {
                    if selectedTab == 0 {
                        companionTab
                    } else if selectedTab == 1 {
                        focusTab
                    } else if selectedTab == 2 {
                        aiTab
                    } else {
                        memoryTab
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 580, minHeight: 580)
        .background(
            ZStack {
                Color(red: 0.97, green: 0.98, blue: 0.99)
                LinearGradient(colors: [Color.cyan.opacity(0.06), Color.blue.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .onAppear {
            loadSettingsData()
        }
    }
    
    // MARK: - Tabs
    
    private var companionTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Body Theme & Appearance", icon: "paintbrush.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Active Theme Preset")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Picker("", selection: $activeTheme) {
                            ForEach(ByteTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: activeTheme) { newValue in
                            SettingsManager.shared.activeTheme = newValue
                        }
                        .tint(.cyan)
                    }
                    
                    // Visual Theme Swatches Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ByteTheme.allCases) { theme in
                            Button(action: {
                                activeTheme = theme
                                SettingsManager.shared.activeTheme = theme
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(theme.shellColor))
                                        .overlay(Circle().stroke(Color(theme.eyeColor), lineWidth: 2))
                                        .frame(width: 14, height: 14)
                                    Text(theme.rawValue)
                                        .font(.system(size: 11, weight: activeTheme == theme ? .bold : .regular))
                                        .foregroundColor(activeTheme == theme ? Color(red: 0.06, green: 0.09, blue: 0.16) : Color(red: 0.35, green: 0.40, blue: 0.50))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(activeTheme == theme ? Color.cyan.opacity(0.18) : Color(red: 0.94, green: 0.96, blue: 0.98))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(activeTheme == theme ? Color.cyan : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }

            SettingsCard(title: "Personality Profile", icon: "face.smiling") {
                HStack {
                    Text("Personality Persona")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                    Spacer()
                    Picker("", selection: $activePersonality) {
                        ForEach(PersonalityProfile.allCases, id: \.self) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: activePersonality) { newValue in
                        SettingsManager.shared.activePersonality = newValue
                    }
                    .tint(.cyan)
                }
            }
            
            SettingsCard(title: "Activity Mode", icon: "slider.horizontal.3") {
                Picker("Behavior Profile", selection: $petMode) {
                    Text("Auto (Smart Focus)").tag("Auto")
                    Text("Work Mode (Quiet)").tag("Work")
                    Text("Play Mode (Active)").tag("Play")
                    Text("Sleep Mode").tag("Sleep")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            SettingsCard(title: "Audio & Speech", icon: "speaker.wave.2.fill") {
                Toggle("Mute Voice Output", isOn: $isMuted)
                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                    .onChange(of: isMuted) { newValue in
                        AudioManager.shared.stopSpeaking()
                    }
            }
        }
    }
    
    private var focusTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Developer Context", icon: "laptopcomputer") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active IDE / App:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text(DeveloperContextMonitor.shared.currentContext.activeAppName.isEmpty ? "None" : DeveloperContextMonitor.shared.currentContext.activeAppName)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Detected Language:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text(DeveloperContextMonitor.shared.currentContext.detectedLanguage)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                    HStack {
                        Text("Current Focus State:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text(FocusEngine.shared.currentFocusLevel.rawValue.capitalized)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Visual Vision Engine:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text(ByteVisionEngine.shared.activeEngineName)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    HStack {
                        Text("Perception Mode:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text("Event-Driven & On-Demand (0% Idle)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Visual Perception Context:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text(ByteVisionEngine.shared.formattedVisionContextForAI())
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
    
    private var aiTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "LLM & Voice Pipeline", icon: "brain") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use Gemini Cloud API (Fallback)", isOn: $useCloudAI)
                        .toggleStyle(SwitchToggleStyle(tint: .cyan))
                        .onChange(of: useCloudAI) { newValue in
                            if newValue {
                                AIEngine.shared.provider = GeminiAPIProvider(apiKey: "AQ.Ab8RN6JquuZTkTTYuwK4u8G1zZeUG6NXcKmWbqVohVFvSbyawA")
                            } else {
                                AIEngine.shared.provider = LocalOllamaProvider()
                            }
                        }
                    
                    HStack {
                        Text("Active LLM Model:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text(useCloudAI ? "Gemini 2.5 Flash" : "Ollama byte-llm (Local)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Vision Model:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text("Florence-2-Base (232M / Port 9005)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    HStack {
                        Text("STT Engine:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text("faster-whisper (Port 9000)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("TTS Engine:")
                            .foregroundColor(Color(red: 0.35, green: 0.40, blue: 0.50))
                        Spacer()
                        Text("Kokoro-82M (Port 8880)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
    }
    
    private var memoryTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Learned Behavioral Rules", icon: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 6) {
                    let rules = MemoryGraph.shared.getBehavioralRulesString()
                    Text(rules)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.32))
                }
            }
            
            SettingsCard(title: "Personal Facts Learned", icon: "text.badge.checkmark") {
                VStack(alignment: .leading, spacing: 6) {
                    let facts = MemoryGraph.shared.getUserFactsString()
                    Text(facts)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.32))
                }
            }
        }
    }
    
    private func loadSettingsData() {
        // Hydrate data from singletons
        activePersonality = SettingsManager.shared.activePersonality
        activeTheme = SettingsManager.shared.activeTheme
    }
}

// MARK: - Helper Views

struct TabButton: View {
    let title: String
    let icon: String
    let index: Int
    @Binding var selectedTab: Int
    
    var isSelected: Bool { selectedTab == index }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? .blue : Color(red: 0.35, green: 0.40, blue: 0.50))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                Spacer()
            }
            Divider()
                .background(Color(red: 0.88, green: 0.91, blue: 0.94))
            content
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.88, green: 0.91, blue: 0.94), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

