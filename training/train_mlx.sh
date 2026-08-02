#!/bin/bash
# High-Accuracy Masked LoRA Fine-Tuning on Apple Silicon Metal GPU with MLX

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🚀 Step 1: Formatting prompt/completion dataset & 3-way split..."
python3 "$SCRIPT_DIR/prepare_compact_train.py"

echo "📦 Step 2: Verifying Python dependencies..."
python3 -m pip install -q mlx-lm mlx huggingface_hub

echo "🧠 Step 3: Starting Loss-Masked Metal GPU Fine-Tuning (Rank 32, Masked Prompt)..."
# Using --mask-prompt ensures loss is ONLY computed over completion tokens!
# Using --config lora_config.yaml (rank 32, alpha 64, all projection layers)
# Using --num-layers -1 (train all layers)
python3 -m mlx_lm.lora \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --data "$SCRIPT_DIR" \
    --train \
    --mask-prompt \
    --config "$SCRIPT_DIR/lora_config.yaml" \
    --num-layers -1 \
    --iters 2000 \
    --batch-size 4 \
    --learning-rate 3e-4 \
    --val-batches 25 \
    --adapter-path "$SCRIPT_DIR/adapters"

echo "⚙️ Step 4: Fusing LoRA adapters into compact standalone model..."
python3 -m mlx_lm.fuse \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --adapter-path "$SCRIPT_DIR/adapters" \
    --save-path "$SCRIPT_DIR/byte_fused_model"

echo "🦙 Step 5: Registering trained model in Ollama..."
if command -v ollama &> /dev/null; then
    ollama create byte-llm -f "$SCRIPT_DIR/ByteModelfile" || true
fi

echo "========================================================"
echo "🎉 TRAINING & MODEL FUSION COMPLETE!"
echo "Model Location: $SCRIPT_DIR/byte_fused_model"
echo "Ollama Model  : byte-llm"
echo "========================================================"
