# 🧠 Byte Fine-Tuning & Customization Suite

This directory contains everything you need to fine-tune and customize Byte's dialogue and action LLM locally on your Mac using **Apple MLX** and **Ollama**.

---

## 📁 Files Included

- **`ByteModelfile`**: Ollama model configuration specifying Byte's persona, system prompt, and formatting constraints (`[ACTION: xxx] [EMOTION: xxx]`).
- **`generate_dataset.py`**: Python script to generate structured training (`train.jsonl`) and validation (`valid.jsonl`) datasets.
- **`train_mlx.sh`**: Shell script to run Apple Silicon LoRA fine-tuning using `mlx-lm` on your Mac's Metal GPU.

---

## 🚀 Quickstart

### Method 1: Instant Ollama Customization (No Training Required)

Run the following command to register Byte's custom model directly in Ollama:

```bash
ollama create byte-llm -f training/ByteModelfile
```

Then Byte will automatically use your custom model!

---

### Method 2: Apple MLX LoRA Fine-Tuning (Full Weight Training)

1. Make the training script executable:
   ```bash
   chmod +x training/train_mlx.sh
   ```

2. Run local fine-tuning on your Mac:
   ```bash
   ./training/train_mlx.sh
   ```

3. Export the fused model into Ollama and start chatting!
