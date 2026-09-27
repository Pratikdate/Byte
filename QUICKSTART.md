# Quick Start

Get Byte running in a few minutes. This walks through the one-command launch
path, what's happening behind the scenes, and how to fix the most common
first-run problems.

## 1. Prerequisites

- macOS 14.0 (Sonoma) or newer.
- [Xcode](https://developer.apple.com/xcode/) 15+ (for building the app).
- Python 3.9+ (for the local AI microservices).
- [Ollama](https://ollama.ai) — powers Byte's local chat brain.

## 2. Clone & build

```bash
git clone https://github.com/Pratikdate/Byte.git
cd Byte
open DesktopPet.xcodeproj
# Cmd+B to build, Cmd+R to run
```

The first launch calls `BackgroundServerManager` inside the app, which finds
(or starts) every local service Byte needs — you don't have to run anything
by hand. If you'd rather manage the services yourself, or you're doing
backend development, use the launcher script instead:

```bash
chmod +x start.sh
./start.sh
```

## 3. What's running

Byte is one Swift app talking to a small stack of local, offline servers.
None of these send data off your Mac.

| Port | Service | Role |
|---|---|---|
| 11434 | Ollama (`byte-llm`) | Fine-tuned chat brain — every reply carries an `[ACTION: ...] [EMOTION: ...]` tag that drives the 3D animation |
| 9000 | `backend/whisper_server.py` | Speech-to-text (faster-whisper) |
| 8880 | `backend/tts_server.py` | Text-to-speech (Kokoro) |
| 9005 | `backend/florence_vision_server.py` | Reads on-screen text/code so Byte can react to what you're looking at |
| 9006 | `backend/personaplex_server.py` | **Experimental** full-duplex speech engine (see note below) — falls back to Kokoro/system voice automatically |

`start.sh` will print which of these it started vs. found already running,
and shuts all of them down cleanly on Ctrl+C.

> **PersonaPlex-7B is a work in progress.** The server on port 9006 stands
> up NVIDIA's PersonaPlex-7B API surface (`/health`, `/prompt`,
> `/synthesize_speech`, `/ws/duplex`), but the actual model weights aren't
> wired up yet — it always serves placeholder audio and reports
> `is_mock: true`. Byte automatically falls back to Kokoro or the system
> voice, so this doesn't block normal use. If you want to help finish real
> inference, start in [backend/personaplex_server.py](backend/personaplex_server.py).

## 4. Try it out

- Click and drag Byte around the desktop — physics-based throw included.
- Hold **⌘ (Command)** to talk — Byte listens, transcribes locally, and
  replies out loud.
- Open **Settings** (right-click the pet → Settings) to see live status for
  every engine, switch personas, and inspect Byte's memory of you.
- Leave Byte idle for a while — the Q-learning brain wanders, perches, and
  sleeps on its own, and gets slightly better at picking actions over time.

## 5. Troubleshooting

| Problem | Fix |
|---|---|
| No voice, or a system-default voice instead of Byte's | Kokoro (port 8880) isn't running — check `curl http://localhost:8880/health` (it should say `byte-kokoro-tts`). Byte still works via the macOS fallback voice. |
| Byte doesn't understand speech | Check the Whisper server: `curl http://localhost:9000/health`. If it's down, `start.sh` will restart it on next launch. |
| Chat replies feel generic / not "Byte" | By default `byte-llm` is the base Llama 3.2 1B with Byte's prompt. Train and compare the fine-tune with the steps under "Deploying the Fine-Tune" in the [README](README.md) (about 50 MB of disk). |
| App won't build | Confirm the Xcode scheme target is macOS and the Swift toolchain is 5.9+. |
| Byte forgot everything after a restart | Memories now live in `~/Library/Application Support/Byte/`. Older builds saved them to the launch directory, which is `/` when opened from Finder, so they were lost. Existing files in the project root are copied over automatically on first launch. |
| Want Byte to forget you | Quit Byte and delete `~/Library/Application Support/Byte/`. |
| Ollama not found | The app will ask you (via a macOS notification) to install it from [ollama.ai](https://ollama.ai) — it will not install anything on your Mac without asking. |

## Next steps

- Full architecture and training pipeline: [README.md](README.md)
- Empathy model training deep-dive: [docs/EMPATHY_TRAINING_AND_ML_ARCHITECTURE.md](docs/EMPATHY_TRAINING_AND_ML_ARCHITECTURE.md)
- Local audio setup details: [docs/LOCAL_AUDIO_SETUP.md](docs/LOCAL_AUDIO_SETUP.md)
