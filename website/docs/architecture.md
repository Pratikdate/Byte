---
id: architecture
title: Core Architecture
sidebar_position: 1
---

# Core Architecture

The Byte project is structured into distinct managers and engines to ensure a clean separation of concerns, providing extreme speed and modularity.

## `PetBrain.swift`
The central state machine. Evaluates conditions (energy depletion, annoyance levels) and dictates the active `PetState` protocol implementation (e.g., Idle, Wander, Sleep).

## `AIEngine.swift`
The analytical layer. Synthesizes data from the environment (weather, time, active apps) and generates prompts/decisions. It infers user intent from broken or complex voice sentences using a Local LLM.

## `ReinforcementLearningModel.swift`
The native Swift Q-Learning engine that drives Byte's autonomous physical actions based on environmental state rewards and penalties.

## `ReflectionEngine.swift` & `MemoryGraph.swift`
The self-improvement loop. Analyzes user feedback logs (`FeedbackLogger.swift`) during sleep cycles to deduce permanent behavioral rules and store user facts.

## `VoiceInputManager.swift`
Handles offline speech-to-text via `faster-whisper` and realistic text-to-speech via `Kokoro`.

## `DesktopEnvironmentManager.swift`
Utilizes macOS Accessibility APIs (`AXUIElement`) to read window frames and track active applications, allowing Byte to interact physically with your open apps.
