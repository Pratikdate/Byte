---
id: architecture
title: Core Architecture
sidebar_position: 1
---

# Core Architecture

The Byte project is structured into a clean four-layer system architecture to ensure a clear separation of concerns, operating primarily offline for maximum privacy and performance. Data flows in one direction only: **Sensors → State → Behavior/Emotion → Rendering**. No layer calls a non-adjacent layer directly.

## 1. OS Sensor Layer
**Role:** Subscribes to system events continuously and ambiently.
**Implementation:**
- Watches the Downloads folder via `FSEvents`
- Checks battery and CPU status via `IOKit`
- Listens to active app switching via `NSWorkspace`
- Captures idle state and mouse clicks/drags globally via `NSEvent`

## 2. State Engine (`PetBrain.swift`)
**Role:** A plain Swift tick-based engine (~10Hz) that manages internal state variables (energy, mood, curiosity, annoyance, routine_phase, attention_target) completely independent of UI or rendering.
**Implementation:** OS events *nudge* these variables, which decay or rise over time. The engine uses Utility AI to score candidate actions rather than relying on a rigid dispatch table.

## 3. Emotion + Behavior Layer (`AIEngine.swift`)
**Role:** Collapses continuous state numbers into discrete, readable emotions and behavior selections.
**Implementation:** 
- Translates state scores into specific emotion labels (e.g., Content, Excited, Sleepy, Annoyed).
- Selects dialogue using Apple's on-device `FoundationModels` framework for fast, offline flavor text.
- Optionally uses the Anthropic API (Claude) only when explicit talk-mode is invoked by the user.

## 4. Rendering & OS Integration
**Role:** Draws the character and manages window presence.
**Implementation:** Uses a transparent, click-through, always-on-top `NSWindow` built with `AppKit`. Rendering relies entirely on `SpriteKit` for animation loops, posture changes, and particle emitters (like hearts or sweat), requiring no bulky external engines.
