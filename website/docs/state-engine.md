---
id: state-engine
title: State Engine & Emotions
sidebar_position: 2
---

# State Engine & Emotions

At the core of Byte's personality is the **State Engine** (implemented in plain Swift), operating at a ~10Hz tick. Unlike traditional game characters that rely on rigid dispatch tables (`event → animation`), Byte's behavior and emotions emerge dynamically from continuously evaluating internal variables.

## Core State Variables

Byte maintains six core variables (typically scored 0–100):

| Variable | Rises from | Falls from | Drives |
|---|---|---|---|
| `energy` | Scheduled/idle sleep | Active hours, interactions | Wake/sleep state, animation speed |
| `mood` | Clicks/petting (in moderation), celebrations, novelty | Prolonged neglect, over-poking, low battery | Baseline emotional tone |
| `curiosity` | Novelty (new file, new app, cursor movement) | Time since last novel event | Wander vs. idle decision, surprise reactions |
| `annoyance` | Rapid repeated clicks/drags within a short window | Time passing with no further poking | Irritated/annoyed emotion, temporary cursor-avoidance |
| `attention_target`| Pointer, not decaying (set on new focus) | Reset on new focus | What the pet looks at / walks toward |
| `routine_phase` | Scheduled clock (wake/work/lunch/nap/evening/sleep) | — | Baseline bias on all other variables |

## Utility AI Action Scoring

Each tick, the engine evaluates candidate actions (e.g., idle, wander, sleep, greet, celebrate) using a utility AI approach.

An action's score is calculated using:
- The base utility of the action
- The current values of `energy`, `mood`, `curiosity`, `annoyance`, and `routine_phase` multiplied by specific weights
- A small randomness/jitter factor

The action with the highest resulting score is selected for execution.

## Emotion Resolution

While the state engine produces continuous numbers, the emotion layer collapses them into discrete, readable emotions every tick. This ensures the renderer always has exactly one clear expression to draw, avoiding ambiguous faces.

### Emotion States

| Emotion | Typical Trigger | Expression Cues |
|---|---|---|
| **Content** | Energy high, mood high, curiosity/annoyance low | Relaxed eyes, slow blink, gentle idle sway |
| **Excited** / **Playful** | Mood high, curiosity high | Wide eyes, bouncy movement, quick tail/ear flick |
| **Curious** / **Surprised** | Sudden `curiosity` spike (e.g., new file/app) | Eyes widen briefly, head tilt toward target |
| **Sleepy** | Energy low, routine phase = evening/night | Slow blink, drooping posture, yawns |
| **Asleep** | Energy very low or routine phase = sleep | Eyes closed, "Zzz" particle, unresponsive to minor events |
| **Annoyed** | `annoyance` high (over-poking) | Narrowed eyes, small shake, cursor-avoidance movement |
| **Lonely** / **Sad** | Mood low sustained over a long neglect period | Droopy posture, slower movement, dimmer particle color |
| **Startled** | Very sharp, sudden `curiosity` or `annoyance` spike | Quick jump, wide eyes, brief freeze before resuming |
| **Bored** | Curiosity low sustained with no novelty | Slower idle loop, occasional sigh animation |

### Design Constraints
- Emotions are mutually exclusive.
- To transition from one extreme to another (e.g., Annoyed to Excited), Byte must pass through `Content` for at least one tick to ensure transitions feel continuous and not glitchy.
