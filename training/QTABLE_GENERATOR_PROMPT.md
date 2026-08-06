# 🧠 Q-Table Generator Guide & LLM Master Prompt

Byte uses **Continuous Reinforcement Learning** driven by two local Q-Tables:

1. **`rl_qtable.json`** — Behavioral Q-Table (State: `[timeOfDay, attentionState, hasActiveWindows]` -> Actions: `[sitOnCorner, sleep, jump, ...]`)
2. **`spatial_qtable.json`** — Spatial Movement Q-Table (State: `0..8` screen sector -> Action: `0..8` target sector)

---

## ⚡ Instant Base Generation (Script)

You can generate or reset pre-trained base Q-Tables anytime using the local script:

```bash
python3 training/generate_base_qtables.py
```

This populates all 30 environmental state combinations and 81 spatial grid movement transitions with optimal Q-values so Byte starts with intelligent behaviors out-of-the-box.

---

## 📋 Frontier LLM Master Prompt for Q-Table Fine-Tuning (Claude 3.5 / GPT-4o)

If you want to use an advanced frontier model to customize or expand the Q-Tables, use the prompt below:

```text
You are an expert Reinforcement Learning (RL) engineer building baseline Q-Tables for 'Byte' — an intelligent 3D desktop pet companion on macOS.

--- TASK 1: BEHAVIORAL Q-TABLE (`rl_qtable.json`) ---
Format MUST be a JSON array of alternating elements: [StateObject, ActionsMapObject, StateObject, ActionsMapObject, ...].

State Object Format:
{"hasActiveWindows": boolean, "timeOfDay": "morning"|"afternoon"|"evening"|"night"|"lateNight", "attentionState": "idle"|"active"|"engaged"}

Actions Map Format (Assign Q-values from -1.0 to +1.0):
{
  "idle": float, "wander": float, "sleep": float, "sit": float, "jump": float, "spin": float,
  "sitOnCorner": float, "sitOnMenuBar": float, "climbWindow": float, "wave": float,
  "backflip": float, "headbang": float, "sneeze": float, "tapWindow": float, "pushWidget": float
}

Reinforcement Learning Rules:
1. When user is 'engaged' (working/coding): High positive rewards (+0.7 to +0.9) for quiet/subtle actions (sitOnCorner, sitOnMenuBar, climbWindow). Severe penalties (-0.5 to -0.8) for loud/distracting actions (headbang, backflip, sneeze).
2. When timeOfDay is 'night' or 'lateNight': High rewards (+0.8) for sleep and sit. Penalties for noisy actions.
3. When user attention is 'active' (interacting): High rewards (+0.8 to +1.0) for playful/interactive actions (wave, jump, spin, backflip, tapWindow).

--- TASK 2: SPATIAL MOVEMENT Q-TABLE (`spatial_qtable.json`) ---
Format MUST be a single JSON object mapping "state_action" keys to double Q-values:
Key format: "<from_sector>_<to_sector>" where sector is 0..8 (3x3 grid: 0=top-left, 2=top-right, 4=center, 6=bottom-left, 8=bottom-right).

Spatial RL Rules:
1. Moving to corners (0, 2, 6, 8) or center (4) gets high rewards (+0.6 to +0.9).
2. Neighboring 1-step moves get high rewards (+0.7).
3. Staying in exact same spot (distance=0) gets low/neutral reward (+0.05).

Generate valid JSON output for both Q-Tables following these rules.
```
