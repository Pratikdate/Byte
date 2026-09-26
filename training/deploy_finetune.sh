#!/bin/bash
# Deploys a Byte LoRA fine-tune to Ollama as byte-llm:v2-lora.
#
# Lightweight: Ollama applies the adapter (~20-50 MB, converted to GGUF) on top of the
# llama3.2:1b it already has, so no multi-GB fused copy is written.
#
#   ./training/deploy_finetune.sh [adapter_dir]        (default: training/adapters_1b)
#
# Train a new adapter first with:
#   cd training && python3 -m mlx_lm lora -c lora_config_1b.yaml
#
# This does NOT repoint `byte-llm` (what the app uses). It prints a head-to-head against
# the current model on real app-style prompts; promote only if it wins:
#   ollama cp byte-llm byte-llm:pre-lora-backup && ollama cp byte-llm:v2-lora byte-llm

set -euo pipefail

TRAINING_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$TRAINING_DIR"

ADAPTER_DIR="${1:-adapters_1b}"
TAG="${TAG:-byte-llm:v2-lora}"   # override: TAG=byte-llm:v3-lora ./deploy_finetune.sh

if [ ! -f "$ADAPTER_DIR/adapters.safetensors" ]; then
    echo "❌ No adapter weights at $ADAPTER_DIR/adapters.safetensors. Train one first (see header)." >&2
    exit 1
fi

echo "🧬 Converting $ADAPTER_DIR to a GGUF LoRA..."
python3 build_lora_gguf.py "$ADAPTER_DIR" byte_lora.gguf

echo "📦 Creating $TAG (base llama3.2:1b + adapter, Llama 3.2 chat template it was trained with)..."
ollama create "$TAG" -f ByteModelfile.lora

echo "🔍 Head-to-head on app-style prompts:"
python3 compare_models.py byte-llm "$TAG"
