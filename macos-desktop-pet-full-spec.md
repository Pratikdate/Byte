# macOS desktop pet — build specification

**Purpose of this document:** a self-contained implementation brief. It does not assume the reader has any other context — everything needed to start building is here.

**Target platform:** macOS 26 (Tahoe) or later, Apple Silicon only.
**Core idea:** a small creature that lives on the desktop continuously, with its own internal state, a range of readable emotions, and a daily rhythm — rather than a chat assistant with an avatar. Presence over utility, personality over productivity.

---

## Table of contents

1. Design philosophy
2. System architecture
3. Tech stack
4. Open-source references
5. macOS permissions and entitlements
6. LLM strategy
7. State engine specification
8. Emotion model
9. Behavior repertoire
10. Sensor integration
11. UI/UX specification
12. Build roadmap with acceptance criteria
13. Risks and mitigations
14. Starter code

---

## 1. Design philosophy

Two rules govern every decision in this document:

**A. Simulation, not a dispatch table.** The pet is not `event → animation` lookup. It has internal state variables (energy, mood, curiosity, annoyance, routine phase) that decay continuously and interact. OS events and user interactions *nudge* these variables; emotion and behavior *emerge* from the current state, chosen by scoring functions, not hardcoded per-event responses.

**B. Local first, network last.** Every ambient behavior — movement, reactions, emotional expression, flavor text — runs entirely on-device, no network dependency. A cloud LLM call is reserved for exactly one explicit, user-initiated feature (click-to-talk), never for anything that happens on its own.

**Success metric for the whole project:** people who run it for a week notice its absence when they shut the Mac down. Feature completeness is not the success metric — that reaction is.

---

## 2. System architecture

Four layers. Data flows one direction only: sensors → state → behavior/emotion → rendering. No layer calls a non-adjacent layer directly.

```
┌─────────────────────────────────────────────────────────────┐
│  OS SENSOR LAYER                                              │
│  FSEvents (Downloads folder) · IOKit (battery/CPU)             │
│  NSWorkspace (active app) · NSEvent (idle, click, drag)         │
└───────────────────────────┬────────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  STATE ENGINE (plain Swift, no UI dependency, ~10Hz tick)       │
│  energy · mood · curiosity · annoyance · attention_target       │
│  · routine_phase                                                │
└───────────────────────────┬────────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  EMOTION + BEHAVIOR LAYER                                       │
│  State → discrete emotion label · utility-AI action scoring     │
│  · dialogue picker (template + LLM)                             │
└───────────────────────────┬────────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  RENDERING / OS INTEGRATION                                      │
│  Transparent click-through NSWindow · SpriteKit animator         │
│  (expression, posture, particles)                                │
└─────────────────────────────────────────────────────────────┘
```

**Critical rule:** sensors never call rendering directly, and nothing skips the emotion layer. A click on the pet does not directly trigger a "happy" animation — it nudges `mood` and `annoyance`, and the emotion layer resolves the current combination of variables into an emotion label and picks an animation for it. This is what keeps the emotional responses coherent (a pet that's already annoyed from over-poking shouldn't flip straight to delighted from one more click) instead of a shallow reflex.

---

## 3. Tech stack

| Component | Choice | Why |
|---|---|---|
| App shell | SwiftUI (menu bar item, settings popover) | Native, minimal boilerplate for non-pet chrome |
| Pet window | `NSWindow`, manual (`AppKit`) | SwiftUI `WindowGroup` cannot produce a transparent, click-through, always-on-top, all-spaces window — requires direct `NSWindow` control |
| Rendering | SpriteKit | Free, built into macOS, handles sprite sheets/texture atlases/basic physics and particle emitters (for hearts, sweat, Zzz) with no external dependency |
| Behavior/state/emotion engine | Plain Swift, no framework | Must stay portable and unit-testable, independent of AppKit/SpriteKit |
| On-device dialogue | `FoundationModels` framework | Apple's ~3B-parameter on-device model — free, offline, no API key, built for short dialog/creative generation |
| Optional cloud dialogue | Anthropic API (Claude Haiku-class) via the same `LanguageModelSession` protocol (macOS 26+) | Reserved for explicit "talk mode" only |
| Folder watching | `FSEvents` / `DispatchSource` | Native, no polling |
| Battery/CPU | `IOKit` | Native power-source and thermal APIs, no permission required |
| App/notification awareness | `NSWorkspace` | Native active-app and workspace notifications, no permission required |
| Idle/cursor/click/drag tracking | `NSEvent` global monitor | Native input event taps — requires Accessibility permission |
| Packaging/signing | Xcode + Developer ID + notarization | Required for Gatekeeper to allow an always-on-top overlay app to launch cleanly |

**Do not use Electron or any cross-platform shell.** The target is Mac-only, and native AppKit/SpriteKit gives deeper OS integration and a lower memory/battery footprint than a bundled Chromium runtime for an app meant to run continuously in the background.

---

## 4. Open-source references

Real, actively maintained Swift/macOS projects doing close variants of this idea. Verify each repo's license (typically MIT or Apache) before reusing code commercially.

- **desktop-goose** — Swift port of "Desktop Goose," using SpriteKit and Apple's Foundation Models framework already. Closest reference in spirit and stack — study its window setup and animation patterns first.
- **TapBuddy** — reacts to keyboard and mouse input; reference for input-driven reactions.
- **Pixel-art SpriteKit companion projects** (search GitHub topics `desktop-pet` and `desktop-mascot`, filtered to Swift) — several implement moods, eye-follow, and typing reactions in Swift + SpriteKit; useful for animation state machine and mood-rendering patterns even if the art is replaced.
- **apfel** — CLI and OpenAI-compatible local server front-end for Apple's on-device model; useful for hitting the on-device model over HTTP during development/testing.
- **LlamaBarn** — menu bar app for managing local LLMs on a Mac; optional reference only if a heavier local model is later wanted alongside Apple's on-device one.

**Do not reuse anything derived from reverse-engineering Living.AI's EMO device.** Community projects that intercept EMO's private API traffic are not licensed assets — obtained by intercepting a commercial device's proprietary traffic. It is also unnecessary: this specification's own emotion and behavior model (Sections 8–9) covers the same ground legitimately, built from scratch on top of Apple's own frameworks.

---

## 5. macOS permissions and entitlements

macOS requires each sensitive capability to be requested individually, the first time it is actually used — not in bulk at launch.

| Feature | macOS mechanism | User-visible prompt |
|---|---|---|
| Cursor/keyboard/click/drag tracking outside the app's own window | Accessibility (Input Monitoring) via `NSEvent.addGlobalMonitorForEvents` | One-time system prompt + manual toggle in System Settings → Privacy & Security → Accessibility. Cannot be silently pre-approved. |
| Downloads folder watching | App Sandbox + `com.apple.security.files.downloads.read-write` entitlement | **None**, if sandboxed with this specific entitlement — pre-approved by the OS. Without sandboxing, requires the user to pick the folder once via `NSOpenPanel`. |
| Battery level, CPU load | `IOKit` | None — public, unrestricted API |
| Active app / window focus changes | `NSWorkspace` notifications | None — public, unrestricted API |
| On-device dialogue generation | `FoundationModels` framework | None from the app itself; requires the device-wide Apple Intelligence toggle to be on |
| Reading another app's notification content | No public API exists for this | Not achievable through supported means — design around it |
| App launching at all | Developer ID signing + notarization | One-time Gatekeeper dialog if properly signed/notarized |

**Design constraint on notifications:** there is no supported way to read the *content* of another app's notifications on macOS. React to *that* a notification/context change occurred via `NSWorkspace`, not what it says.

**Implementation guidance:**
- Request Accessibility only when the cursor-follow/click-detection feature first needs to activate, not at app launch.
- Set a clear, honest `NSAccessibilityUsageDescription` string in Info.plist.
- Enable App Sandbox and request the `com.apple.security.files.downloads.read-write` entitlement to avoid needing Full Disk Access.
- Handle code signing and notarization as a release-time step, separate from runtime permission logic.

---

## 6. LLM strategy

Two tiers, split by who initiated the interaction:

1. **Ambient tier — on-device Foundation Models, always.** Every unprompted behavior (mood comments, folder nudges, greetings, weather reactions, reactions to being petted or over-poked) runs through Apple's ~3B-parameter on-device model. Zero network latency, zero cost, works offline.
2. **Talk-mode tier — Claude (Haiku-class), on explicit user request only.** When the user clicks the pet to start a real conversation, swap models for that one session.

**Implementation note:** `LanguageModelSession` on macOS 26 supports swapping the underlying model through one consistent API — talk mode requires no separate integration path.

**Guided generation:** define dialogue output as a `@Generable` Swift struct with fields for `emotion`, `text`, `animation_hint`, so output is type-checked at the token level and directly usable by the rendering layer.

**Never call an LLM to decide *what* the pet does or *feels*.** Emotion and behavior are always computed locally by Sections 8–9. The model only generates wording for a state the engine already determined.

---

## 7. State engine specification

Six variables, each `0–100` unless noted, evaluated on a ~10Hz tick:

| Variable | Rises from | Falls from | Drives |
|---|---|---|---|
| `energy` | scheduled/idle sleep | active hours, interactions | wake/sleep, animation speed |
| `mood` | clicks/petting (in moderation), celebrations, novelty | prolonged neglect, over-poking, low battery | baseline emotional tone |
| `curiosity` | novelty (new file, new app, cursor movement) | time since last novel event | wander vs. idle decision, surprise reactions |
| `annoyance` | rapid repeated clicks/drags within a short window ("over-poking") | time passing with no further poking | irritated/annoyed emotion, temporary cursor-avoidance behavior |
| `attention_target` | pointer, not decaying — set on new focus | reset on new focus | what the pet looks at / walks toward |
| `routine_phase` | scheduled clock (wake/work/lunch/nap/evening/sleep) | — | baseline bias on all other variables |

**Selection method: utility AI.** Each tick, score every candidate action against the current variables plus small randomness, execute the highest-scoring one. The emotion layer (Section 8) reads the same variables in parallel to choose how that action is *expressed*.

**Pseudocode for one tick:**
```
for each candidate action in [idle, wander, react_to_cursor, comment_on_folder,
                              sleep, greet, celebrate, avoid_cursor, play]:
    score = action.baseUtility
          + weight_energy    * f(energy, action)
          + weight_mood      * f(mood, action)
          + weight_curiosity * f(curiosity, action)
          + weight_annoyance * f(annoyance, action)
          + weight_routine   * f(routine_phase, action)
          + random(-jitter, +jitter)
best_action = argmax(scores)
emotion = resolveEmotion(energy, mood, curiosity, annoyance)
execute(best_action, styled_by: emotion)
```

---

## 8. Emotion model

The state engine produces continuous numbers; the emotion layer collapses them into one of a small set of discrete, readable emotions each tick, so the renderer always has exactly one clear expression to draw rather than blending numbers directly into ambiguous faces.

**Emotion labels and their triggering conditions:**

| Emotion | Typical trigger | Expression cues |
|---|---|---|
| Content | energy high, mood high, curiosity low, annoyance low | relaxed eyes, slow blink, gentle idle sway |
| Excited / playful | mood high, curiosity high | wide eyes, bouncy movement, quick tail/ear flick |
| Curious / surprised | sudden `curiosity` spike (new file, new app opened) | eyes widen briefly, head tilt toward `attention_target` |
| Sleepy | energy low, routine phase = evening/night | slow blink, drooping posture, yawns |
| Asleep | energy very low or routine phase = sleep | eyes closed, "Zzz" particle, no reaction to minor events |
| Annoyed | `annoyance` high (over-poking) | narrowed eyes, small shake, brief cursor-avoidance movement |
| Lonely / sad | mood low sustained over a long neglect period | droopy posture, slower movement, dimmer particle color |
| Startled | very sharp, sudden `curiosity` or `annoyance` spike | quick jump, wide eyes, brief freeze before resuming |
| Bored | curiosity low sustained with no novelty for a long period | slower idle loop, occasional sigh animation |

**Design rules:**
- Emotions are mutually exclusive at any tick — the renderer never draws two at once. Resolve ties by priority order: `Startled > Annoyed > Sleepy/Asleep > Curious > Excited > Lonely > Bored > Content`.
- No emotion should be able to flip instantly from one extreme to another (e.g., Annoyed straight to Excited) — require passing through `Content` for at least one tick, so transitions read as continuous rather than glitchy.
- Expression cues are drawn from a small, reusable set of primitives (eye shape, blink rate, posture lean, particle overlay) rather than a unique rig per emotion — this keeps the animation asset list bounded (see Section 9's asset list) instead of growing per emotion indefinitely.

---

## 9. Behavior repertoire

This is the concrete list of things the pet can *do*, each one an action the utility-AI in Section 7 can select, each styled by the current emotion from Section 8.

| Behavior | Triggered by | Notes |
|---|---|---|
| Idle sway / look around | default, low curiosity | 3–5 variants to avoid an obviously looping tell |
| Wander to a point on screen | high curiosity, no specific target | picks a nearby empty desktop area |
| Follow cursor with eyes/head | cursor moves nearby | does not always chase the cursor bodily — mostly just looks |
| Walk toward the Downloads folder and comment | folder gains new files | uses on-device dialogue, styled by current mood |
| Celebrate | a download completes, or mood is very high | brief bounce/sparkle particle, short burst then returns to idle |
| Greet | routine phase transitions to "wake" or user returns after long idle | short greeting line via dialogue picker |
| Nap / sleep | energy low or routine phase = night | closed eyes, reduced reaction sensitivity to minor events |
| React to petting (single click) | one click on the pet's sprite | brief happy bounce, small mood increase |
| Show annoyance / avoid cursor | rapid repeated clicks within a short window | narrowed eyes, brief shake, and a short cooldown period where it moves away from the cursor rather than following it — mirrors how a real pet would react to being poked too much, and is an intentional design constraint, not a bug: constant clickability would undercut the "living creature" feel |
| Get picked up / dragged | click-and-drag on the sprite | dangling posture while dragged, small "wheee" or startled reaction depending on drag speed |
| Look tired / sweat | battery low or sustained high CPU load | posture droops, small sweat-drop particle |
| Trip over a desktop shortcut | rare, random, only when mood is high and curiosity is high | pure comic animation, no state consequence — a deliberate "imperfection" beat, not a state-driven reaction |
| Look outside / react to weather | optional: time-of-day lighting change on the wallpaper region, or a lightweight weather check | changes idle expression subtly (brighter for clear, droopier for overcast) — keep this a rare ambient touch, not a frequent interruption |
| Play (lightweight) | mood high, curiosity high, user actively moves the cursor near the pet for a few seconds | pet "chases" a small area around the cursor briefly, then returns to idle — a light-touch stand-in for a game, not a full mini-game system in v1 |

**What is intentionally out of scope for v1:** full mini-games (memory games, rhythm games, shooting games), voice recognition, and audio-reactive dancing. These require significant additional systems (game state, microphone/audio-tap permissions, and speech recognition) disproportionate to the "ambient companion" goal of this build. Treat them as possible post-v1 extensions only after Section 12's Phase 6 validation confirms the core concept is worth the extra investment — not before.

**Animation asset checklist derived from Sections 8–9** (build these once, reuse across emotions/behaviors rather than commissioning unique art per row above):
- Eye states: open, narrowed, wide, closed, half-closed (blinking)
- Body postures: upright, slouched, bouncy, dangling (dragged), frozen (startled)
- Particles: heart (happy), sweat drop (tired/hot), Zzz (asleep), sparkle (celebrate), small cloud (annoyed)
- Movement cycles: idle sway ×3-5 variants, walk, quick shake, bounce, freeze-then-resume

---

## 10. Sensor integration

| Sensor | API | State nudge |
|---|---|---|
| Downloads folder contents | `FSEvents` | `curiosity` up, `attention_target` = folder |
| Battery level | `IOKit` power source | `energy` ceiling lowers when battery low |
| CPU load | `IOKit` / `host_processor_info` | `mood` dips slightly under sustained load |
| Active app changes | `NSWorkspace` notifications | `attention_target` = new active app context |
| Mouse position / idle time | `NSEvent` global monitor | drives cursor-follow; `energy` decays faster while active, pet sleeps after an idle threshold |
| Click on pet sprite | `NSEvent` global monitor + hit-test | single click → `mood` up slightly; rapid repeated clicks within a short window → `annoyance` up |
| Drag on pet sprite | `NSEvent` global monitor + hit-test | triggers "picked up" behavior, no lasting state change unless dragged very roughly |

Route every sensor through the state engine — never let a sensor call rendering or emotion resolution directly (see Section 2's critical rule).

---

## 11. UI/UX specification

**Placement:** the pet renders low on the screen, near the dock, not centered — grounded and peripheral, not demanding attention.

**Window behavior:**
- Transparent, click-through (`ignoresMouseEvents = true`) by default.
- Briefly toggle `ignoresMouseEvents = false` only to hit-test a click/drag directly on the pet's sprite bounds.
- Always-on-top, all-spaces (`.canJoinAllSpaces, .stationary`), but auto-hide when a fullscreen app is frontmost.

**Menu bar presence:** a small persistent menu bar icon (simplified pet face, ideally reflecting current emotion at a glance) is the only always-visible control surface. Clicking it opens a settings popover with:
- "Show pet" toggle
- "Sounds" toggle
- "Activity level" slider (maps to how aggressively curiosity/boredom trigger actions)

**Dialogue presentation:** a small speech bubble appears near the pet only when the state/emotion engine decides a comment is warranted, stays a few seconds, then fades. Never a persistent chat window.

**Sizing:** render the pet at roughly 48–72px tall on a Retina display.

**Visual reference (screen composition, described for an agent without image access):**
```
┌───────────────────────────────────────────────────┐
│ Finder                          Wi-Fi  Battery  ●  │ ← menu bar, ● reflects current emotion
├───────────────────────────────────────────────────┤
│                                                     │
│  [Downloads folder icon]   ["looks like it's       │
│                              getting messy"]        │
│                                    ▲                │
│                                  [pet]               │ ← pet sits low, near dock
│                                                     │
│              ▢ ▢ ▢ ▢ ▢  (dock icons)                │
└───────────────────────────────────────────────────┘
```

---

## 12. Build roadmap with acceptance criteria

**Phase 1 (week 1–2): presence only, no state logic**
- Build: transparent click-through `NSWindow`, one SpriteKit idle/walk/sleep animation, cursor-follow.
- Acceptance: watching it move for 10 minutes feels charming, not annoying, with zero AI involved. If this fails, do not proceed.

**Phase 2 (week 3): the state engine**
- Build: energy/mood/curiosity/annoyance/routine variables ticking at ~10Hz, utility-AI action selection replacing any hardcoded loop.
- Acceptance: behavior is visibly less repetitive than Phase 1 with identical assets.

**Phase 3 (week 4): emotion layer and expanded behaviors**
- Build: the emotion resolution function from Section 8, plus click/drag/petting/annoyance behaviors from Section 9.
- Acceptance: a person watching cold (no explanation) can correctly guess the pet's emotional state most of the time, and clicking it rapidly produces a visibly different reaction than a single gentle click.

**Phase 4 (week 5): sensors**
- Build: Downloads folder watch, battery, idle detection wired in as state nudges per Section 10.
- Acceptance: reactions feel proportionate to what is actually happening.

**Phase 5 (week 6): daily routine**
- Build: scheduled routine phases (wake/lunch/nap/evening/sleep) biasing the state engine.
- Acceptance: the pet has a rhythm independent of user activity.

**Phase 6 (week 7+): dialogue**
- Build: on-device Foundation Models call for flavor text, gated by the state/emotion engine. Optional click-to-talk mode using Claude.
- Acceptance: lines feel contextually and emotionally appropriate, and do not repeat noticeably within a week of daily use.

**Phase 7: real-world validation**
- Put the build in front of 5–10 people who leave it running for a full week.
- Acceptance, and the actual success metric for the whole project: people leave it running, and some report noticing its absence when they shut the Mac down.

---

## 13. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Overlay window drains battery/CPU running 24/7 | Target under 2% idle CPU; profile starting in Phase 1 |
| Gatekeeper blocks an unsigned always-on-top app | Developer ID signing and notarization before distribution |
| Fullscreen apps/games get covered by the overlay | Auto-hide when a fullscreen app is frontmost |
| Dialogue repeats within days | Maintain at least 15–20 lines per context/emotion bucket |
| Sandbox entitlements block folder watching later | Decide sandboxing posture before Phase 4 |
| Over-scoping emotions/behaviors delays v1 | Build only the emotion set and behavior list in Sections 8–9 for v1; treat mini-games/voice/audio-reactive features as explicitly out of scope until Phase 7 validates the core concept |
| Annoyance mechanic feels punishing rather than charming | Keep the annoyed cooldown brief (a few seconds) and always resolve back to content — the goal is a moment of personality, not a "penalty" for interacting with the pet |

---

## 14. Starter code

**Transparent click-through overlay window**
```swift
let window = NSWindow(
    contentRect: NSScreen.main!.frame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.level = .floating
window.backgroundColor = .clear
window.isOpaque = false
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
window.contentView = SKView(frame: window.frame)
```

**Minimal emotion resolution function (illustrative, not production-tuned)**
```swift
enum Emotion {
    case content, excited, curious, sleepy, asleep, annoyed, lonely, startled, bored
}

func resolveEmotion(energy: Double, mood: Double, curiosity: Double, annoyance: Double) -> Emotion {
    if annoyance > 80 { return .annoyed }
    if energy < 10 { return .asleep }
    if energy < 25 { return .sleepy }
    if curiosity > 85 { return .curious }
    if mood > 70 && curiosity > 60 { return .excited }
    if mood < 20 { return .lonely }
    if curiosity < 15 { return .bored }
    return .content
}
```

**Minimal on-device dialogue call**
```swift
import FoundationModels

let session = LanguageModelSession(instructions: """
You are a small desktop pet. Speak in short, plain sentences,
under 12 words. Never use exclamation points more than once per line.
Match your tone to the given emotion.
""")

func comment(on context: String, emotion: String) async throws -> String {
    try await session.respond(to: "Emotion: \(emotion). Context: \(context)").content
}
```

Wire both functions behind the state engine's tick loop from Section 7 — never call emotion resolution or dialogue directly from a sensor or from UI code.

---

**End of specification.** An implementing agent should build in the phase order given in Section 12, checking each phase's acceptance criterion before proceeding to the next.
