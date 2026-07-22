#!/bin/bash
# Fine-tuning Byte locally on Apple Silicon using Apple MLX

echo "🚀 Setting up Apple MLX fine-tuning environment..."

# 1. Install MLX LM tool
python3 -m pip install mlx-lm

# 2. Generate master training dataset
python3 training/download_and_build_master_dataset.py

# 3. Run LoRA Fine-Tuning
echo "🧠 Starting LoRA training on Mac GPU..."
python3 -m mlx_lm.lora \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --data ./training \
    --train \
    --iters 100 \
    --batch-size 1 \
    --learning-rate 1e-4

# 4. Fuse weights and export
echo "📦 Fusing trained LoRA weights..."
python3 -m mlx_lm.fuse \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --save-path ./training/byte_fused_model

echo "✅ Training complete! Fused model saved to ./training/byte_fused_model"
