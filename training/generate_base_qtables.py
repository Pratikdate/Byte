#!/usr/bin/env python3
"""
Base Q-Table Generator for Byte AI Companion

Generates pre-trained baseline Q-Tables for:
1. Behavioral Q-Table (`rl_qtable.json`) — Optimal action selection across time of day, user attention, and window state.
2. Spatial Q-Table (`spatial_qtable.json`) — Optimal 3x3 screen grid movement matrix (states 0..8 -> actions 0..8).
"""

import json
import os

# Project paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
RL_QTABLE_PATH = os.path.join(PROJECT_ROOT, "rl_qtable.json")
SPATIAL_QTABLE_PATH = os.path.join(PROJECT_ROOT, "spatial_qtable.json")

TIMES_OF_DAY = ["morning", "afternoon", "evening", "night", "lateNight"]
ATTENTION_STATES = ["idle", "active", "engaged"]
HAS_WINDOWS = [True, False]

ACTIONS = [
    "idle", "wander", "sleep", "sit", "jump", "spin",
    "sitOnCorner", "sitOnMenuBar", "climbWindow",
    "wave", "backflip", "headbang", "sneeze", "tapWindow", "pushWidget"
]


def generate_behavioral_qtable():
    """Constructs a comprehensive behavioral Q-table dictionary in Swift JSON format."""
    table_pairs = []

    for time_of_day in TIMES_OF_DAY:
        for attention in ATTENTION_STATES:
            for windows in HAS_WINDOWS:
                state = {
                    "hasActiveWindows": windows,
                    "timeOfDay": time_of_day,
                    "attentionState": attention
                }

                action_values = {}
                for act in ACTIONS:
                    val = 0.0

                    # 1. Late Night & Night rules: favor sleep and calm sitting
                    if time_of_day in ["night", "lateNight"]:
                        if act in ["sleep", "sit"]:
                            val += 0.75
                        elif act in ["sitOnCorner", "sitOnMenuBar"]:
                            val += 0.5
                        elif act in ["headbang", "backflip", "jump", "sneeze"]:
                            val -= 0.6

                    # 2. Morning / Afternoon working (engaged attention)
                    if attention == "engaged":
                        if act in ["sitOnCorner", "sitOnMenuBar", "climbWindow", "sit"]:
                            val += 0.8
                        elif act in ["idle", "wander"]:
                            val += 0.3
                        elif act in ["headbang", "backflip", "sneeze", "pushWidget"]:
                            val -= 0.5

                    # 3. Active user attention (interacting, pet bonding)
                    if attention == "active":
                        if act in ["wave", "jump", "spin", "backflip", "tapWindow"]:
                            val += 0.85
                        elif act in ["sit", "sitOnCorner"]:
                            val += 0.4

                    # 4. Active desktop windows present
                    if windows:
                        if act in ["climbWindow", "sitOnCorner", "tapWindow"]:
                            val += 0.45

                    action_values[act] = round(val, 4)

                table_pairs.append(state)
                table_pairs.append(action_values)

    return table_pairs


def generate_spatial_qtable():
    """Generates optimal spatial movement matrix for 3x3 screen grid (0..8)."""
    spatial_table = {}

    # 3x3 Grid:
    # 0 (Top-Left)     1 (Top-Center)    2 (Top-Right)
    # 3 (Mid-Left)     4 (Center)        5 (Mid-Right)
    # 6 (Bottom-Left)  7 (Bottom-Center) 8 (Bottom-Right)

    for state in range(9):
        for action in range(9):
            key = f"{state}_{action}"

            # Calculate grid coordinates (row, col)
            s_row, s_col = divmod(state, 3)
            a_row, a_col = divmod(action, 3)

            distance = abs(s_row - a_row) + abs(s_col - a_col)

            # High value for moving to corners (0, 2, 6, 8) or center (4)
            corner_center_bonus = 0.4 if action in [0, 2, 4, 6, 8] else 0.1

            if distance == 0:
                # Staying in same spot: neutral to small penalty
                val = 0.05
            elif distance == 1:
                # Immediate neighbor: optimal fluid movement
                val = 0.65 + corner_center_bonus
            elif distance == 2:
                # Diagonal or 2-step hop: good movement
                val = 0.45 + corner_center_bonus
            else:
                # 3 or 4 step teleport: slightly lower preference
                val = 0.25 + corner_center_bonus

            spatial_table[key] = round(val, 4)

    return spatial_table


def main():
    print("🧠 Generating Byte Base Q-Tables...")

    # 1. Behavioral Q-Table
    rl_data = generate_behavioral_qtable()
    with open(RL_QTABLE_PATH, "w", encoding="utf-8") as f:
        json.dump(rl_data, f, indent=2)
    print(f"✅ Created Behavioral Q-Table: {RL_QTABLE_PATH} ({len(rl_data)//2} states initialized)")

    # 2. Spatial Q-Table
    spatial_data = generate_spatial_qtable()
    with open(SPATIAL_QTABLE_PATH, "w", encoding="utf-8") as f:
        json.dump(spatial_data, f, indent=2)
    print(f"✅ Created Spatial Q-Table: {SPATIAL_QTABLE_PATH} ({len(spatial_data)} state-action pairs initialized)")


if __name__ == "__main__":
    main()
