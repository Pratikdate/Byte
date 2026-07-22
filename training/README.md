# 🧠 Byte Fine-Tuning & Customization Suite

This directory contains everything you need to fine-tune and customize Byte's dialogue and action LLM (`byte-llm`) locally on your Mac using **Apple MLX** and **Ollama**.

---

## 📁 Files Included

- **`ByteModelfile`**: Ollama model configuration specifying Byte's persona, system prompt, and formatting constraints (`[ACTION: xxx] [EMOTION: xxx]`).
- **`download_and_build_master_dataset.py`**: Python script to fetch baseline conversation datasets and assemble the master dataset.
- **`generate_dataset.py`**: Python script to generate structured training (`train.jsonl`) and validation (`valid.jsonl`) datasets.
- **`train_mlx.sh`**: Shell script to run Apple Silicon LoRA fine-tuning and model fusion using `mlx-lm` on Metal GPU.

---

## 🚀 Quickstart

### Method 1: Instant Ollama Customization (No Training Required)

Run the following command to register Byte's custom model directly in Ollama:

```bash
ollama create byte-llm -f training/ByteModelfile
```

Then Byte will automatically connect to `byte-llm` in Ollama!

---

### Method 2: Apple MLX LoRA Fine-Tuning (Full Weight Training)

1. **Build Master Training Dataset**:
   ```bash
   python3 training/download_and_build_master_dataset.py
   ```

2. **Run Apple Silicon LoRA Fine-Tuning**:
   ```bash
   chmod +x training/train_mlx.sh
   ./training/train_mlx.sh
   ```

3. **Register Fused Model in Ollama**:
   ```bash
   ollama create byte-llm -f training/ByteModelfile
   ```

