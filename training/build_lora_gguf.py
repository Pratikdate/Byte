"""Convert an MLX LoRA adapter into a GGUF LoRA that Ollama can load with ADAPTER.

Why: Ollama runs the base Llama 3.2 model already on disk and applies this ~20-50 MB
adapter on top, so deploying a fine-tune needs no multi-GB fused copy of the weights.

Usage:
    python3 build_lora_gguf.py [adapter_dir] [output.gguf]
    ollama create byte-llm:v2-lora -f ByteModelfile.lora

The adapter must have been trained with mlx_lm on the same base model family that
ByteModelfile.lora uses (Llama 3.2 Instruct).
"""
import json
import os
import sys

import mlx.core as mx
import numpy as np
from huggingface_hub import hf_hub_download
from safetensors import safe_open

# mlx_lm module names -> llama.cpp GGUF tensor names
GGUF_NAMES = {
    "self_attn.q_proj": "attn_q",
    "self_attn.k_proj": "attn_k",
    "self_attn.v_proj": "attn_v",
    "self_attn.o_proj": "attn_output",
    "mlp.gate_proj": "ffn_gate",
    "mlp.up_proj": "ffn_up",
    "mlp.down_proj": "ffn_down",
}


def permute(w: np.ndarray, n_head: int) -> np.ndarray:
    """llama.cpp stores Q/K rows in a rotary-friendly order (convert_hf_to_gguf's
    LlamaModel.permute). LoRA B matrices for q_proj/k_proj must match that order,
    or the adapter silently corrupts attention."""
    return w.reshape(n_head, 2, w.shape[0] // n_head // 2, *w.shape[1:]).swapaxes(1, 2).reshape(w.shape)


def main() -> None:
    adapter_dir = sys.argv[1] if len(sys.argv) > 1 else "adapters_1b"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "byte_lora.gguf"

    cfg = json.load(open(os.path.join(adapter_dir, "adapter_config.json")))
    rank = cfg["lora_parameters"]["rank"]
    scale = cfg["lora_parameters"]["scale"]
    base = json.load(open(hf_hub_download(cfg["model"], "config.json")))
    n_head, n_kv = base["num_attention_heads"], base["num_key_value_heads"]

    weights = safe_open(os.path.join(adapter_dir, "adapters.safetensors"), "np")
    tensors = {}
    for key in weights.keys():
        # model.layers.N.<module>.lora_a|lora_b
        prefix, which = key.rsplit(".", 1)
        parts = prefix.split(".")
        layer, module = parts[2], ".".join(parts[3:])
        # MLX computes x @ A @ B with A (in, r), B (r, out); GGUF wants A (r, in), B (out, r).
        t = weights.get_tensor(key).T
        if which == "lora_b" and module == "self_attn.q_proj":
            t = permute(t, n_head)
        elif which == "lora_b" and module == "self_attn.k_proj":
            t = permute(t, n_kv)
        tensors[f"blk.{layer}.{GGUF_NAMES[module]}.weight.{which}"] = mx.array(
            np.ascontiguousarray(t.astype(np.float32)))

    mx.save_gguf(out_path, tensors, {
        "general.architecture": "llama",
        "general.type": "adapter",
        "general.name": "byte-llm-lora",
        "adapter.type": "lora",
        # mlx_lm scales the LoRA update by `scale`; llama.cpp by alpha / rank.
        "adapter.lora.alpha": mx.array(float(scale * rank), dtype=mx.float32),
    })
    print(f"Wrote {out_path}: {len(tensors)} tensors, rank {rank}, alpha {scale * rank:g}, base {cfg['model']}")


if __name__ == "__main__":
    main()
