---
id: sensors-and-os
title: Sensors & OS Integration
sidebar_position: 4
---

# Sensors & OS Integration

Byte uses native macOS APIs to passively monitor the system and environment without polling. All sensor data is passed to the State Engine to gently nudge internal variables. **Sensors never call rendering or emotion resolution directly.**

## Monitored Events

| Sensor Target | macOS API | Impact on State |
|---|---|---|
| **Downloads folder contents** | `FSEvents` | `curiosity` rises, `attention_target` points to folder |
| **Battery level** | `IOKit` power source | `energy` ceiling lowers when battery is low |
| **CPU load** | `IOKit` / `host_processor_info` | `mood` dips slightly under sustained heavy load |
| **Active app changes** | `NSWorkspace` notifications | `attention_target` points to the new active app context |
| **Mouse position / Idle time** | `NSEvent` global monitor | Drives cursor-follow; `energy` decays faster while active; sleeps after idle threshold |
| **Click on pet sprite** | `NSEvent` global monitor + hit-test | Single click raises `mood`; rapid repeated clicks raise `annoyance` |
| **Drag on pet sprite** | `NSEvent` global monitor + hit-test | Triggers "picked up" behavior (no lasting state change unless dragged roughly) |

## macOS Permissions & Entitlements

macOS requires specific permissions to run these sensors. Byte requests these only when the capability is first needed, never in bulk at launch.

1. **Accessibility (Input Monitoring):** Required for `NSEvent.addGlobalMonitorForEvents` to track the cursor, idle time, clicks, and drags. Users must manually enable this in System Settings.
2. **App Sandbox Entitlement:** Using `com.apple.security.files.downloads.read-write` allows passive `FSEvents` watching of the Downloads folder without needing Full Disk Access.
3. **No Permissions Required:** `IOKit` (battery/CPU) and `NSWorkspace` (active app notifications) use unrestricted public APIs and do not require user prompts.

## UI / UX Setup

- **The Window:** A transparent, click-through (`ignoresMouseEvents = true`) `NSWindow` that is `.floating`, `.canJoinAllSpaces`, and `.stationary`.
- **Interaction:** The window briefly toggles `ignoresMouseEvents = false` only to hit-test a click or drag specifically on Byte's sprite bounds.
- **Menu Bar:** A persistent, minimal menu bar icon exists for settings (sounds, activity level slider).
