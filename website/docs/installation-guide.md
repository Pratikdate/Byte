---
id: installation-guide
title: Installation & Quickstart
sidebar_position: 3
---

# Installation & Quickstart Guide

This guide walks you through setting up and running **Byte** on your Mac.

---

## ⚡ Prerequisites

- **OS:** macOS 14.0 (Sonoma) or newer on Apple Silicon (M1/M2/M3/M4) or Intel Mac.
- **Xcode:** Xcode 15 or newer.
- **Python:** Python 3.9+ with `pip`.
- **Ollama:** Download and install from [ollama.ai](https://ollama.ai).

---

## 🚀 Step-by-Step Setup

### Step 1: Clone Repository
```bash
git clone https://github.com/your-username/Byte.git
cd Byte
```

### Step 2: Run Universal Launcher
Run the single start script to launch Ollama, Whisper STT, Kokoro TTS, and build/open `DesktopPet.app`:
```bash
chmod +x start.sh
./start.sh
```

---

## 🧠 Training & Model Fine-Tuning

### 1. Build Master Dataset from Open-Source EmpatheticDialogues
```bash
python3 training/download_and_build_master_dataset.py
```

### 2. Run Apple Silicon LoRA Fine-Tuning
```bash
chmod +x training/train_mlx.sh
./training/train_mlx.sh
```

### 3. Register Custom Model in Ollama
```bash
ollama create byte-llm -f training/ByteModelfile
```

---

## 🔍 Troubleshooting

- **Ollama Error:** Ensure Ollama desktop app is installed and running (`ollama list`).
- **Xcode Build Errors:** Ensure active Xcode command line tools are selected (`xcode-select --install`).
