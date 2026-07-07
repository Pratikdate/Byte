# Local Audio Pipeline Setup for Byte

Complete guide to set up faster-whisper (speech-to-text) + Kokoro TTS (text-to-speech) on your Mac. Everything runs locally—no cloud APIs.

## Architecture

```
🎤 Microphone
    ↓
[faster-whisper] (port 9000) → transcribe audio to text
    ↓
Text ↔ Byte's Brain (Gemma 2B via Ollama)
    ↓
[Kokoro TTS] (port 8000) → generate natural speech
    ↓
🔊 Speaker
```

## Prerequisites

- **macOS 13+** (Intel or Apple Silicon)
- **8GB RAM minimum** (all models run quantized/lightweight)
- **Ollama** (for Gemma 2B LLM)
- **Python 3.9+** (for faster-whisper + Kokoro servers)

## Step 1: Install Ollama + Gemma 2B

```bash
# Download Ollama from https://ollama.ai
# Then:
ollama pull gemma:2b
ollama serve
```

Ollama runs on `localhost:11434` by default.

## Step 2: Set Up faster-whisper Server

```bash
# Clone or install faster-whisper
pip install faster-whisper

# Create a simple HTTP server wrapper (save as whisper_server.py)
cat > whisper_server.py << 'EOF'
from faster_whisper import WhisperModel
from flask import Flask, request, jsonify
import numpy as np

app = Flask(__name__)
model = WhisperModel("small")  # or "tiny" for 2GB RAM

@app.route('/transcribe', methods=['POST'])
def transcribe():
    audio_data = np.frombuffer(request.data, dtype=np.float32)
    segments, info = model.transcribe(audio_data, language="en")
    text = " ".join([seg.text for seg in segments])
    return jsonify({
        "text": text,
        "is_final": True
    })

if __name__ == '__main__':
    app.run(host='localhost', port=9000)
EOF

python whisper_server.py
```

Runs on `localhost:9000`.

## Step 3: Set Up Kokoro TTS Server

```bash
# Clone Kokoro
git clone https://github.com/hexgrad/Kokoro.git
cd Kokoro

# Install dependencies
pip install -r requirements.txt

# Create HTTP wrapper (save as tts_server.py)
cat > tts_server.py << 'EOF'
from flask import Flask, request, jsonify, send_file
from kokoro import generate  # Adjust based on actual Kokoro API
import io

app = Flask(__name__)

@app.route('/synthesize', methods=['POST'])
def synthesize():
    data = request.json
    text = data.get('text', '')
    emotion = data.get('emotion', 'neutral')
    speed = data.get('speed', 1.0)
    
    # Generate audio with Kokoro
    audio_bytes = generate(text, emotion=emotion, speed=speed)
    
    return send_file(io.BytesIO(audio_bytes), mimetype='audio/wav')

if __name__ == '__main__':
    app.run(host='localhost', port=8000)
EOF

python tts_server.py
```

Runs on `localhost:8000`.

## Step 4: Configure Byte

Update `AudioManager.swift` endpoint URLs if ports differ:

```swift
private let whisperEndpoint = "http://localhost:9000/transcribe"
private let kokoroEndpoint = "http://localhost:8000/synthesize"
```

## Step 5: Run Everything

**Terminal 1** (Ollama):
```bash
ollama serve
```

**Terminal 2** (faster-whisper):
```bash
python whisper_server.py
```

**Terminal 3** (Kokoro TTS):
```bash
python tts_server.py
```

**Terminal 4** (Byte app):
```bash
cd /Users/manishgupta/Downloads/Byte-main
open DesktopPet.xcodeproj
# Build & run in Xcode
```

## Troubleshooting

### Whisper not transcribing
- Check `localhost:9000` is responding: `curl -X POST http://localhost:9000/transcribe`
- Verify microphone permissions in System Settings → Privacy & Security → Microphone

### TTS no audio
- Check Kokoro server: `curl http://localhost:8000/health`
- Check speaker is not muted
- Verify Kokoro model files exist in repo

### Gemma 2B responses slow
- Use smaller model: `ollama pull gemma:2b` (default)
- Or quantized: `ollama pull phi:latest` (smaller, faster)
- Monitor: `watch -n 1 "ps aux | grep ollama"`

## Performance Notes

On 8GB Mac (M1/M2):
- **Whisper (small)**: ~2-3s per 30s audio
- **Gemma 2B**: ~1-2s per response
- **Kokoro TTS**: ~0.5s per sentence

Total latency user → response: **2-4 seconds** (all local, no network).

## Optional: Use system TTS instead of Kokoro

If Kokoro setup is too complex, fall back to macOS's native speech synthesis:

```swift
import AVFoundation

let utterance = AVSpeechUtterance(string: text)
utterance.rate = speedForEmotion(emotion)
let synthesizer = AVSpeechSynthesizer()
synthesizer.speak(utterance)
```

Less natural, but zero setup. Update `AudioManager.swift` to use `AVSpeechSynthesizer` instead of HTTP call.

---

**All processing stays on your Mac. Zero privacy leakage. Offline-first.**
