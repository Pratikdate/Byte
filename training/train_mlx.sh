#!/bin/bash
# Fine-tuning Byte locally on Apple Silicon using Apple MLX

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🚀 Setting up Apple MLX fine-tuning environment..."

# 1. Install MLX LM tool if not present
python3 -m pip install -q mlx-lm

# 2. Build master dataset if train.jsonl does not exist or needs update
echo "📊 Building training dataset..."
python3 "$SCRIPT_DIR/download_and_build_master_dataset.py"

# 3. Run LoRA Fine-Tuning on Apple Metal GPU
echo "🧠 Starting LoRA training on Mac Metal GPU..."
python3 -m mlx_lm.lora \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --data "$SCRIPT_DIR" \
    --train \
    --iters 200 \
    --batch-size 1 \
    --learning-rate 1e-4

# 4. Fuse weights and export
echo "📦 Fusing trained LoRA weights into ./training/byte_fused_model..."
python3 -m mlx_lm.fuse \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --save-path "$SCRIPT_DIR/byte_fused_model"

echo "✅ Training complete! Fused model saved to $SCRIPT_DIR/byte_fused_model"
