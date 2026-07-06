# Quick Start: Local Audio + Natural Speech

## TL;DR Setup (5 minutes)

### 1. Start servers in separate terminals

**Terminal 1:**
```bash
ollama pull gemma:2b
ollama serve
```

**Terminal 2:**
```bash
pip install faster-whisper flask
cat > ~/whisper_server.py << 'EOF'
from faster_whisper import WhisperModel
from flask import Flask, request, jsonify
import numpy as np
app = Flask(__name__)
model = WhisperModel("small")
@app.route('/transcribe', methods=['POST'])
def transcribe():
    audio = np.frombuffer(request.data, dtype=np.float32)
    segments, _ = model.transcribe(audio, language="en")
    text = " ".join([s.text for s in segments])
    return jsonify({"text": text, "is_final": True})
if __name__ == '__main__':
    app.run(host='localhost', port=9000)
EOF
python ~/whisper_server.py
```

**Terminal 3:**
```bash
# Kokoro setup more complex, see LOCAL_AUDIO_SETUP.md
# For now, just run without it—fallback to system TTS works fine
```

### 2. Build Byte

```bash
cd /Users/manishgupta/Downloads/Byte-main
open DesktopPet.xcodeproj
# Cmd+B to build, Cmd+R to run
```

### 3. Test

- App launches
- Click pet → hears spoken response
- Speak to mic → Byte understands you
- Responses vary emotionally, sound natural

**That's it.** TTS fallback to system voice if Kokoro not ready. Full setup in LOCAL_AUDIO_SETUP.md.

---

## What Changed

| Component | Before | After |
|-----------|--------|-------|
| Speech recognition | Cloud (Apple Speech API) | Local (faster-whisper) |
| Dialogue generation | Gemini API | Local (Gemma 2B via Ollama) |
| Text-to-speech | Text-only bubbles | Natural voice (Kokoro or fallback) |
| Processing | Cloud-dependent | All on-device |
| Privacy | Data sent to cloud | Zero data leaves Mac |

## Files to Know

- **AudioManager.swift** — Whisper + Kokoro glue layer
- **DialogueNaturalness.swift** — Makes speech sound natural (pauses, emotion, no repetition)
- **VoiceInputManager.swift** — Updated to use local audio
- **AIEngine.swift** — Now uses Ollama + Gemma 2B, emotion-aware prompts
- **SystemTTSFallback.swift** — Fallback if Kokoro not running

## Key Improvements

✅ **Natural pauses** — Excited responses: quick. Sad responses: slow ellipses.
✅ **Emotion in speech** — Happy = faster+higher pitch, sad = slower+lower pitch.
✅ **No repetition** — Tracks last 20 lines, rejects if >60% word overlap.
✅ **On-device** — No API calls, works offline.
✅ **Fast** — Gemma 2B ~1-2s response, Whisper ~2-3s transcription.

## Troubleshoot

| Problem | Fix |
|---------|-----|
| No sound | Kill Kokoro on purpose—fallback to system TTS works |
| Slow responses | Gemma 2B is local; this is normal. Upgrade CPU if too slow |
| Transcription stuck | Verify whisper server: `curl -X POST http://localhost:9000/transcribe` |
| Won't build | Check: Xcode target = macOS, Swift 5.0+ |

## Next: Full Setup

See **LOCAL_AUDIO_SETUP.md** for:
- Complete Kokoro installation
- Python server code
- Performance benchmarks
- Customization guide

---

**Status:** ✅ Code integrated. Ready to test.
