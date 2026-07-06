# Integration Checklist & Next Steps

## ✅ Completed

### New Modules
- [x] **AudioManager.swift** — Whisper STT + Kokoro TTS wrapper (with fallback)
- [x] **DialogueNaturalness.swift** — Emotion-aware pauses, breathing points, deduplication
- [x] **SystemTTSFallback.swift** — macOS native TTS fallback
- [x] **VoiceInputManager.swift** — Rewritten to use local whisper (removed Apple SFSpeechRecognizer)
- [x] **AIEngine.swift** — Updated to Gemma 2B, naturalness integration, emotional tones

### Documentation
- [x] LOCAL_AUDIO_SETUP.md — Complete server setup guide
- [x] IMPLEMENTATION_SUMMARY.md — Architecture & changes overview
- [x] This checklist

### Code Quality
- [x] Syntax validated (no TypeErrors)
- [x] macOS compatibility (AVAudioSession removed)
- [x] Error handling (Kokoro → fallback to system TTS)
- [x] Memory management (temp file cleanup)

## ⚠️ Before Building

### 1. Project Structure
These files added to `/DesktopPet` folder:
```
DesktopPet/
├── AudioManager.swift          ← NEW
├── DialogueNaturalness.swift   ← NEW
├── SystemTTSFallback.swift     ← NEW
├── VoiceInputManager.swift     ← MODIFIED
└── AIEngine.swift              ← MODIFIED
```

### 2. Server Setup Required

You need to have these running BEFORE testing audio features:

**Terminal 1: Ollama (Gemma 2B)**
```bash
ollama pull gemma:2b
ollama serve
# Listens on localhost:11434
```

**Terminal 2: faster-whisper server**
```bash
cd ~/whisper_server  # or wherever you set it up
python whisper_server.py
# Listens on localhost:9000
```

**Terminal 3: Kokoro TTS server**
```bash
cd ~/Kokoro
python tts_server.py
# Listens on localhost:8000
```

(See LOCAL_AUDIO_SETUP.md for server code)

### 3. Xcode Integration

1. **Open project:**
   ```bash
   open DesktopPet.xcodeproj
   ```

2. **Check build target:** DesktopPet (macOS)

3. **Build:** Cmd+B
   - Should succeed (all new files have valid Swift syntax)

4. **Run:** Cmd+R
   - App launches
   - Verify: no crashes on startup

### 4. Testing Flow

**Stage 1: No voice (text-only)**
- [ ] App runs without servers
- [ ] Click pet → text response appears
- [ ] No TTS errors in console

**Stage 2: With system TTS fallback**
- [ ] Kokoro server NOT running
- [ ] Click pet → hears system voice response
- [ ] Verify: emotion affects pitch + speed

**Stage 3: With Kokoro TTS**
- [ ] All 3 servers running
- [ ] Click pet → hears natural Kokoro voice
- [ ] Verify: responses have emotion-aware pauses

**Stage 4: Speech input**
- [ ] Whisper server running
- [ ] Mic button → speaks to Byte
- [ ] Verify: real-time transcription (onTranscriptionUpdate)
- [ ] Verify: Byte responds to what you said

**Stage 5: Naturalness**
- [ ] Get same emotion response 3x in a row → should vary
- [ ] Check console logs:
   - No "Failed to decode" errors
   - No "Kokoro TTS unavailable" (unless intentional test)

## 🔧 Configuration & Customization

### Change LLM provider:
In `AIEngine.swift`, line ~374:
```swift
// Default (recommended)
var provider: AIProvider = LocalOllamaProvider()

// Or switch to:
var provider: AIProvider = Local2BLLMProvider()  // faster-inference server
```

### Adjust emotional tone:
In `AIEngine.swift`, method `emotionalInstructions()`:
```swift
case "happy":
    return "Speak with MORE energy! Super bouncy rhythm."  // Make it bouncier
```

### Fine-tune naturalness:
In `DialogueNaturalness.swift`:

**Longer/shorter pauses:**
```swift
// Line ~30, addEmotionalPauses()
case "sleepy":
    result = result.replacingOccurrences(of: ".", with: "..... ")  // More ellipses
```

**Dialogue repetition threshold:**
```swift
// Line ~95, ensureVariation()
if maxWords > 0 && Float(overlap) / Float(maxWords) > 0.5 {  // 50% instead of 60%
```

**TTS speed by emotion:**
```swift
// Line ~50, VoiceInputManager.swift
case "excited": return 1.3  // Even faster
```

## 📋 Troubleshooting

| Issue | Solution |
|-------|----------|
| "Kokoro TTS unavailable" in logs | Start Kokoro server on port 8000 (see LOCAL_AUDIO_SETUP.md) |
| No audio output | Check speaker isn't muted; verify system TTS fallback works |
| Transcription not updating | Ensure whisper server running on port 9000 |
| Responses feel slow | Gemma 2B ~1-2s is normal; switch to smaller model if needed |
| Responses repeat exactly | Increase dialogue history size or lower repetition threshold |
| Can't start Ollama | Check: `ollama --version`, pull model: `ollama pull gemma:2b` |

## 🚀 Next Phase (Optional)

### Voice cloning
- User records sample voice
- Kokoro TTS uses that voice instead of default
- Requires: voice embedding training (1-5 min audio sample)

### Persistent memory
- Store dialogue history beyond current session
- Byte remembers conversations from weeks ago
- Requires: local database (SQLite)

### Music system
- Background ambience based on emotion
- Happy → upbeat, sad → melancholic piano
- Requires: audio mixing + library

### Animation sync
- Byte's lip-sync to TTS output
- Mouth shape matches phoneme timing
- Requires: audio analysis + timing data

## 📞 Testing Checklist

- [ ] Built without errors
- [ ] App launches without crashes
- [ ] Text responses work
- [ ] System TTS fallback works (kill Kokoro server intentionally)
- [ ] Kokoro TTS works (with server running)
- [ ] Whisper transcription works
- [ ] Emotional tone varies (rerun same prompt → different response)
- [ ] Responses don't repeat within session
- [ ] No console errors
- [ ] CPU/memory reasonable (<10% CPU idle, <200MB memory)

---

**Ready to build!** Follow LOCAL_AUDIO_SETUP.md first, then open in Xcode.
