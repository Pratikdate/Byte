# Byte: Intelligent 3D Desktop Pet for macOS

<div align="center">
  <img src="./assets/byte_preview.png" alt="Byte Desktop Pet" />
</div>

<br/>

<p align="center">
  <img src="./assets/motion_walking.png" width="19%" title="Walking & Listening" />
  <img src="./assets/motion_walk_curious.png" width="19%" title="Walk Curious" />
  <img src="./assets/motion_sleeping.png" width="19%" title="Sleeping" />
  <img src="./assets/motion_looking.png" width="19%" title="Looking Forward" />
  <img src="./assets/motion_sideways.png" width="19%" title="Turned Sideways" />
</p>

**Byte** is an open-source, context-aware 3D desktop companion built natively for macOS using Swift and SceneKit. Operating as an overlay on the macOS desktop, Byte interacts with your workspace, responds to system events, and exhibits dynamic AI-driven behaviors based on environmental context.

## 🌟 Key Features

### 🧠 True Machine Learning & Autonomous Brain
Byte relies on a robust hybrid Machine Learning stack running entirely offline on your Mac. For a complete technical deep-dive into the AI architecture, training loops, and memory consolidation, please read our [Machine Learning Architecture](ML_ARCHITECTURE.md) document.
- **Q-Learning Action Model**: Byte's autonomous actions (wandering, sleeping, sitting) are entirely data-driven. He evaluates your current environment state (time of day, active apps, attention state) and uses a native Swift Reinforcement Learning model (`ReinforcementLearningModel`) to pick the mathematically best action based on the Bellman equation.
- **Reflection Engine & Memory Graph**: Byte learns from your feedback! When he goes to sleep, he triggers a self-reflection loop (`ReflectionEngine`). A local LLM acts as an offline trainer, analyzing recent interactions and deducing permanent behavioral rules (saved in a `MemoryGraph`).
- **Context-Aware Intent Deduction**: Powered by a fine-tuned local LLM (`byte-llm` via Ollama), Byte doesn't just parse rigid commands; he infers your intent from long, complex, or even broken sentences using zero-shot inference. See [`training/README.md`](training/README.md) for local Apple Silicon MLX fine-tuning scripts.

### 🗣️ Local Voice & AI Capabilities
- **On-Device Voice I/O**: Completely private and offline voice parsing using `faster-whisper` for Speech-to-Text and `Kokoro` for hyper-realistic Text-to-Speech (`VoiceInputManager`).
- **Dynamic Dialogue**: Byte's speech lines are never hardcoded. Based on his action and environment, he generates witty, context-appropriate dialogue on the fly using `byte-llm`.

### 🎮 3D Rendering & Physics Engine
- **SceneKit Integration**: Fully rendered 3D models with programmatic animations and physics-based interactions.
- **Custom Physics Simulation**: Features custom gravity, velocity, and friction models applied outside of standard SceneKit physics bodies, allowing Byte to interact with macOS UI elements (such as treating the Dock as a physical floor).
- **Interactive Manipulation**: 
  - Free-form drag and drop with calculated trajectory/throw physics.
  - Trackpad and scroll-wheel support for persistent 3D rotation (`manualRotationY`).

### Context-Aware AI & State Machine
- **`PetBrain` State Machine**: Governs behavioral states (Idle, Wander, Sleep, Sulk, Dizzy) with a sophisticated priority queue and emotion mapping (`annoyance`, `energy`, `happiness`).
- **Workspace Awareness (`DesktopEnvironmentManager`)**: Utilizes macOS Accessibility APIs (`AXUIElement`) to track active applications, window positions, and bounds. Byte can dynamically interact with your active windows.
- **Audio & Media Detection (`AudioMonitor`)**: Integrates with `CoreAudio` to detect physical output routes (e.g., connected headphones) and active media playback (Spotify, Apple Music).
- **Real-Time Weather Integration (`WeatherManager`)**: Subscribes to local weather APIs to adapt Byte's behavior to the physical world (e.g., deploying a programmatic 3D umbrella during rain).

## 🏗 Architecture

The project is structured into distinct managers and engines to ensure a clean separation of concerns:

- **`PetScene.swift`**: The core SceneKit rendering and physics loop. Handles the `tick` event for custom gravity, velocity calculations, procedural animations, and mouse event tracking.
- **`PetBrain.swift`**: The state machine. Evaluates conditions (energy depletion, annoyance levels) and dictates the active `PetState` protocol implementation.
- **`ReinforcementLearningModel.swift`**: The native Swift Q-Learning engine that drives Byte's autonomous physical actions based on environmental state rewards and penalties.
- **`AIEngine.swift`**: The analytical layer. Synthesizes data from the environment and generates prompts/decisions to drive spontaneous dialogue and infer intent from voice commands using `byte-llm`.
- **`ReflectionEngine.swift` & `MemoryGraph.swift`**: The self-improvement loop. Analyzes user feedback logs during sleep cycles to deduce permanent behavioral rules.
- **`DesktopEnvironmentManager.swift`**: Handles low-level macOS Accessibility integrations to parse the UI tree.
- **`VoiceInputManager.swift` / `AudioMonitor.swift` / `WeatherManager.swift`**: Dedicated hardware/network observers for voice, media, and local environment states.
- **`training/`**: MLX LoRA training scripts, dataset generators, and Ollama `ByteModelfile` for fine-tuning `byte-llm`.

## 🚀 Getting Started

### Prerequisites
- **OS**: macOS 14.0 (Sonoma) or later
- **IDE**: Xcode 15.0 or later
- **Language**: Swift 5.0+
- **LLM Engine**: [Ollama](https://ollama.com) installed and running locally (`ollama serve`)

### Installation & Build

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/Byte.git
   cd Byte
   ```
2. Create Byte's local model in Ollama:
   ```bash
   ollama create byte-llm -f training/ByteModelfile
   ```
3. Open the project in Xcode:
   ```bash
   open Byte.xcodeproj
   ```
4. Select your local Mac as the build destination and hit `Cmd + R` (Run).
5. **Permissions**: On first launch, macOS will prompt for **Accessibility Permissions**. This is required for `DesktopEnvironmentManager` to read window frames and dock positions. 
   - Go to `System Settings` > `Privacy & Security` > `Accessibility` and toggle the switch for `Byte`.


## 🛠 Contributing

Contributions to Byte are highly encouraged! Whether it's adding new state behaviors, expanding context awareness, or optimizing the physics engine:

1. Fork the project.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

## 📝 License

Distributed under the MIT License. See `LICENSE` for more information.
