---
id: behaviors
title: Behavior Repertoire
sidebar_position: 3
---

# Behavior Repertoire

This document details the concrete list of actions Byte can perform. Each of these is a candidate action that the Utility AI (detailed in the [State Engine](./state-engine)) can select.

When selected, the action is styled by the currently active emotion to produce the final animation.

| Behavior | Triggered by | Notes |
|---|---|---|
| **Idle sway / look around** | Default, low curiosity | 3–5 variants to avoid an obviously looping tell |
| **Wander** | High curiosity, no specific target | Picks a nearby empty desktop area |
| **Follow cursor** | Cursor moves nearby | Mostly just looks, does not always chase bodily |
| **Comment on Downloads** | Folder gains new files | Uses on-device dialogue, styled by current mood |
| **Celebrate** | A download completes, or mood is very high | Brief bounce/sparkle particle, short burst |
| **Greet** | Routine phase transitions to "wake" or user returns | Short greeting line via dialogue picker |
| **Nap / Sleep** | Energy low or routine phase = night | Closed eyes, reduced reaction sensitivity |
| **React to petting** | Single click on the sprite | Brief happy bounce, small mood increase |
| **Show annoyance** | Rapid repeated clicks | Narrowed eyes, brief shake, avoids cursor temporarily |
| **Picked up / Dragged** | Click-and-drag on the sprite | Dangling posture, startled reaction based on drag speed |
| **Look tired / sweat** | Battery low or high CPU load | Posture droops, small sweat-drop particle |
| **Trip over shortcut** | Rare, random (high mood, high curiosity) | Comic animation only, no state consequence |
| **React to weather** | Time-of-day lighting or weather check | Subtle idle expression changes (e.g. droopier if overcast) |
| **Play (lightweight)** | High mood/curiosity + active cursor movement | Pet briefly "chases" cursor, then returns to idle |

## What's Intentionally Out of Scope

To maintain the "ambient companion" feel and minimize system load, the following are intentionally avoided in the v1 build:
- Full mini-games (e.g., rhythm games, memory games)
- Voice recognition triggers
- Audio-reactive dancing

These features demand constant active engagement, whereas Byte is designed for presence over utility.
