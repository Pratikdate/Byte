# Code Flow Diagram: Local Audio Integration

## Speech Output (Pet Speaks to User)

```
PetScene.say(text: String)
    ↓
    → VoiceInputManager.shared.speak(text, emotion)
    ↓
    → AudioManager.speak(text, emotion, speed)
    ↓
    ├─→ DialogueNaturalness.enhanceForSpeech(text, emotion)
    │   ├─→ addEmotionalPauses() [happy=quick, sad=slow]
    │   ├─→ addBreathingPoints() [break at 7 words]
    │   └─→ normalizeForTTS() [remove emojis, expand abbrev]
    │
    ├─→ POST to localhost:8000/synthesize (Kokoro TTS)
    │   └─→ If success → playAudioData() → AVAudioEngine
    │   └─→ If fail → fallback to SystemTTSFallback
    │
    └─→ SystemTTSFallback.speak() (if Kokoro unavailable)
        → AVSpeechSynthesizer (macOS native)
        → Maps emotion → pitch/speed
```

**File locations:**
- `PetScene.say()` → line 1950
- `VoiceInputManager.speak()` → new method
- `AudioManager.speak()` → new file
- `DialogueNaturalness.enhanceForSpeech()` → new file
- `SystemTTSFallback.speak()` → new file

---

## Speech Input (User Speaks to Pet)

```
UI: Mic button clicked
    ↓
    → PetScene.showListeningState(true)
    → Emotion set to curious
    ↓
    → VoiceInputManager.shared.startListening()
    ↓
    → AudioManager.startListening()
    ↓
    → captureAudioAndTranscribe()
        → Streams mic → PCM buffers
        ↓
        → sendAudioToWhisper() 
            → POST to localhost:9000/transcribe
            ↓
            → faster-whisper returns: {"text": "...", "is_final": true/false}
            ↓
            → onTranscriptionUpdate callback
            → onTranscriptionFinished callback (when final)
    ↓
    → PetScene.sayToPet(transcript)
    ↓
    → PetBrain.queryAI(userMessage: transcript)
        → AIEngine.generateAgentDecision()
        → Gemma 2B generates: {action, emotion, speech}
    ↓
    → PetScene.say(speech)
    ↓
    [back to Speech Output flow above]
```

**File locations:**
- `PetScene.showListeningState()` → line 2015
- `PetScene.sayToPet()` → line 2009
- `VoiceInputManager.startListening()` → rewritten
- `AudioManager.startListening()` → new file
- `AIEngine.generateAgentDecision()` → updated

---

## Dialogue Generation (Core Intelligence)

```
AIEngine.generateAgentDecision(context, emotion, userMessage)
    ↓
    → Builds system prompt with:
        ├─→ Current emotion + emotionalInstructions()
        ├─→ User message (if any)
        ├─→ Available actions
        └─→ Behavioral rules from MemoryGraph
    ↓
    → LocalOllamaProvider.generateAgentDecision()
        → POST to localhost:11434/api/generate
        → Model: gemma:2b
        → Returns: {"action": "...", "emotion": "...", "speech": "..."}
    ↓
    → Dialog Naturalness Processing:
        dialogue.speech = DialogueNaturalness.enhanceForSpeech(speech, emotion)
    ↓
    → Return AIAgentDecision
    ↓
    → PetBrain applies action + emotion
    ↓
    → PetScene.say(decision.speech)
    ↓
    [back to Speech Output flow]
```

**File locations:**
- `AIEngine.generateAgentDecision()` → line 446
- `AIEngine.emotionalInstructions()` → line 429
- `LocalOllamaProvider` → line 150 (updated)
- `DialogueNaturalness.enhanceForSpeech()` → new file

---

## Text-Only Comment Generation (Ambient)

```
PetBrain or triggered by environment
    ↓
    → AIEngine.generateComment(context, emotion, userMessage?)
    ↓
    → Builds system prompt with:
        ├─→ Emotion + tone instructions
        ├─→ Random topic hint (for creativity)
        ├─→ No emojis rule
        └─→ Dialogue history (for dedup)
    ↓
    → LocalOllamaProvider.generateComment()
        → POST to localhost:11434/api/generate
        → Model: gemma:2b
        → Returns: "..." (text only)
    ↓
    → Dialogue Naturalness:
        enhanced = DialogueNaturalness.enhanceForSpeech(text, emotion)
    ↓
    → Cache in dialogueHistory (max 20 lines)
    ↓
    → Return to caller
    ↓
    → PetScene.say(enhanced)
```

**File locations:**
- `AIEngine.generateComment()` → line 370
- `AIEngine.dialogueHistory` → tracks last 20 responses
- `DialogueNaturalness.ensureVariation()` → checks against history

---

## Naturalness Processing (Happens Every Speak)

```
DialogueNaturalness.enhanceForSpeech(text, emotion)
    ↓
    → addEmotionalPauses(text, emotion)
    │   Patterns:
    │   Happy:   "."  → ".!  " (punchy)
    │   Sad:     "."  → "... " (slow ellipses)
    │   Curious: "."  → ".?  " (questioning)
    │
    → addBreathingPoints(enhanced)
    │   If length > 15 words:
    │   Split at ~7-word boundaries with \n
    │   Kokoro interprets \n as brief pause
    │
    → normalizeForTTS(enhanced)
    │   Remove: emojis, *, _, #
    │   Replace: "btw"→"by the way", "lol"→"haha"
    │   Clean whitespace
    │
    → ensureVariation(candidate, previousLines)
    │   Check last 5 lines
    │   Reject if >60% word overlap
    │   Reject if exact match in last 3
    │
    → Return final natural-sounding text
```

**File locations:**
- `DialogueNaturalness.enhanceForSpeech()` → main method
- `DialogueNaturalness.addEmotionalPauses()` → line ~30
- `DialogueNaturalness.addBreathingPoints()` → line ~60
- `DialogueNaturalness.normalizeForTTS()` → line ~85
- `DialogueNaturalness.ensureVariation()` → line ~95

---

## Emotion Mapping (TTS Voice Characteristics)

```
Emotion (String) → Speed & Pitch

AIEngine.emotionalInstructions(emotion) → prompt tone
VoiceInputManager.speedForEmotion(emotion) → TTS speed
SystemTTSFallback.speechRateForEmotion(emotion) → native rate
SystemTTSFallback.pitchForEmotion(emotion) → native pitch

Examples:
  "happy", "excited" → 1.2x speed, higher pitch
  "sad", "sleepy" → 0.8x speed, lower pitch
  "curious" → 1.0x speed, slightly raised pitch
  "annoyed" → 1.1x speed, neutral pitch
  default → 1.0x speed, natural pitch
```

**File locations:**
- `AIEngine.emotionalInstructions()` → line 429
- `VoiceInputManager.speedForEmotion()` → new method
- `SystemTTSFallback.speechRateForEmotion()` → new file
- `SystemTTSFallback.pitchForEmotion()` → new file

---

## Fallback Chain (Error Recovery)

```
VoiceInputManager.speak(text, emotion)
    ↓
    → AudioManager.speak(text, emotion, speed)
        ↓
        → POST to Kokoro TTS (port 8000)
        ↓
        ├─ Success → playAudioData() → speaker 🔊
        │
        └─ Error/Timeout (3s) → 
            print("Kokoro TTS unavailable, using system TTS")
            ↓
            → SystemTTSFallback.speak(text, emotion)
            ↓
            → AVSpeechSynthesizer (no network dependency)
            ↓
            → Speaker with emotion (pitch/speed) 🔊
```

**Key:** If Kokoro fails, app still speaks. No error to user.

---

## Server Ports

```
localhost:11434   ← Ollama (Gemma 2B)
                   GET /api/tags
                   POST /api/generate

localhost:9000    ← faster-whisper
                   POST /transcribe
                   Request: audio bytes
                   Response: {"text": "...", "is_final": bool}

localhost:8000    ← Kokoro TTS
                   POST /synthesize
                   Request: {"text": "...", "emotion": "...", "speed": 1.0}
                   Response: WAV audio bytes
```

---

## Data Flow Summary

```
🎤 Mic Input
    ↓
[faster-whisper:9000]
    ↓
💬 Transcribed Text
    ↓
[Gemma 2B:11434]
    ↓
📝 Dialogue Generated
    ↓
[DialogueNaturalness]
    ↓
✨ Natural Text (pauses, emotion)
    ↓
[Kokoro:8000 OR SystemTTS]
    ↓
🔊 Speaker Output
```

**All local. All on-device. Zero cloud.**

---

## Testing Points (Where to Add Breakpoints)

1. **Transcription test:**
   - `AudioManager.sendAudioToWhisper()` → see JSON response

2. **Dialogue generation test:**
   - `AIEngine.generateComment()` completion → see generated text

3. **Naturalness test:**
   - `DialogueNaturalness.enhanceForSpeech()` return value → see pauses added

4. **TTS test:**
   - `AudioManager.playAudioData()` → see audio file created

5. **Emotion test:**
   - `VoiceInputManager.speak()` → verify speed changes per emotion

---

## Configuration Points (What's Tunable)

See each file's header for customization:

| What | File | Method | Line |
|------|------|--------|------|
| Emotion tone hints | AIEngine.swift | emotionalInstructions() | 429 |
| Pause patterns | DialogueNaturalness.swift | addEmotionalPauses() | ~30 |
| Breathing threshold | DialogueNaturalness.swift | addBreathingPoints() | ~60 |
| Repetition threshold | DialogueNaturalness.swift | ensureVariation() | ~95 |
| TTS speed per emotion | VoiceInputManager.swift | speedForEmotion() | new |
| Fallback TTS pitch/speed | SystemTTSFallback.swift | speechRateForEmotion() | new |

---

**End of flow diagram. All wiring complete. Ready to test.**
