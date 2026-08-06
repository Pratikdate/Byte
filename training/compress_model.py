#!/usr/bin/env python3
"""
Byte Model Compressor — Re-quantize the fused model to lower bit-widths.

Strategy: Since the fused model is already 4-bit quantized, we must:
  1. Dequantize it back to full precision (bfloat16)
  2. Re-quantize at the target bit-width (3-bit or 2-bit)

Usage:
    python3 compress_model.py                   # Default: 3-bit compression
    python3 compress_model.py --bits 2          # Aggressive 2-bit compression
    python3 compress_model.py --bits 3 --bits 2 # Try both and compare
"""

import argparse
import json
import os
import shutil
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SOURCE = os.path.join(SCRIPT_DIR, "byte_fused_model")
DEQUANT_DIR = os.path.join(SCRIPT_DIR, ".byte_dequantized_tmp")


def get_model_size_mb(directory):
    """Calculate total size of all files in a directory in MB."""
    total = 0
    for root, _dirs, files in os.walk(directory):
        for f in files:
            total += os.path.getsize(os.path.join(root, f))
    return total / (1024 * 1024)


def run_mlx_cmd(args, label):
    """Run an mlx_lm command with error handling."""
    cmd = [sys.executable, "-m", "mlx_lm.convert"] + args
    print(f"\n🔧 [{label}] Running: {' '.join(cmd)}\n")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout)
    if result.returncode != 0:
        print(f"❌ {label} failed!\n{result.stderr}")
        sys.exit(1)
    return result


def dequantize_model(source_dir):
    """Dequantize the 4-bit fused model back to full precision."""
    print(f"\n{'='*60}")
    print(f"🔓 Step 1: Dequantizing model to full precision (bfloat16)")
    print(f"{'='*60}")
    print(f"  Source : {source_dir}")
    print(f"  Output : {DEQUANT_DIR}")

    if os.path.isdir(DEQUANT_DIR):
        print(f"  ♻️  Removing existing dequantized cache...")
        shutil.rmtree(DEQUANT_DIR)

    run_mlx_cmd([
        "--hf-path", source_dir,
        "--mlx-path", DEQUANT_DIR,
        "--dequantize",
        "--dtype", "bfloat16",
    ], "Dequantize")

    dequant_size = get_model_size_mb(DEQUANT_DIR)
    print(f"  ✅ Dequantized model: {dequant_size:.1f} MB (full precision)")
    return DEQUANT_DIR


def quantize_model(source_dir, bits, group_size, output_dir):
    """Quantize a full-precision model to the specified bit-width."""
    print(f"\n{'='*60}")
    print(f"🗜️  Step 2: Re-quantizing to {bits}-bit (group_size={group_size})")
    print(f"{'='*60}")
    print(f"  Source : {source_dir}")
    print(f"  Output : {output_dir}")

    if os.path.isdir(output_dir):
        print(f"  ♻️  Removing existing output directory...")
        shutil.rmtree(output_dir)

    run_mlx_cmd([
        "--hf-path", source_dir,
        "--mlx-path", output_dir,
        "--quantize",
        "--q-bits", str(bits),
        "--q-group-size", str(group_size),
    ], f"Quantize {bits}-bit")

    # Update config.json with quantization metadata
    config_path = os.path.join(output_dir, "config.json")
    if os.path.exists(config_path):
        with open(config_path, "r") as f:
            config = json.load(f)
        config["quantization"] = {"group_size": group_size, "bits": bits}
        config["quantization_config"] = {"group_size": group_size, "bits": bits}
        with open(config_path, "w") as f:
            json.dump(config, f, indent=4)
        print(f"  ✏️  Updated config.json with {bits}-bit quantization metadata")

    return output_dir


def compress_model(source_dir, bits, group_size, output_dir):
    """Full compression pipeline: dequantize → re-quantize."""
    source_size = get_model_size_mb(source_dir)
    print(f"\n📦 Source model: {source_size:.1f} MB (4-bit quantized)")

    # Step 1: Dequantize to full precision
    dequant_dir = dequantize_model(source_dir)

    # Step 2: Re-quantize at target bits
    quantize_model(dequant_dir, bits, group_size, output_dir)

    output_size = get_model_size_mb(output_dir)
    ratio = (1 - output_size / source_size) * 100 if source_size > 0 else 0

    print(f"\n{'='*60}")
    print(f"✅ Compression complete!")
    print(f"  Original (4-bit) : {source_size:.1f} MB")
    print(f"  Compressed ({bits}-bit): {output_size:.1f} MB")
    print(f"  Reduction        : {ratio:.1f}%")
    print(f"  Output at        : {output_dir}")
    print(f"{'='*60}\n")

    return output_dir


def cleanup_temp():
    """Remove the temporary dequantized model."""
    if os.path.isdir(DEQUANT_DIR):
        print(f"🧹 Cleaning up temporary dequantized model ({get_model_size_mb(DEQUANT_DIR):.0f} MB)...")
        shutil.rmtree(DEQUANT_DIR)
        print("  ✅ Cleaned up.")


def register_ollama(model_dir, model_name):
    """Create an Ollama model from the compressed weights."""
    modelfile_path = os.path.join(SCRIPT_DIR, "ByteModelfile")
    if not os.path.exists(modelfile_path):
        print(f"⚠️  ByteModelfile not found at {modelfile_path}, skipping Ollama registration.")
        return

    if shutil.which("ollama") is None:
        print("⚠️  Ollama not found in PATH, skipping registration.")
        return

    print(f"🦙 Registering compressed model as '{model_name}' in Ollama...")
    try:
        subprocess.run(["ollama", "create", model_name, "-f", modelfile_path],
                        check=True, capture_output=True, text=True)
        print(f"✅ Ollama model '{model_name}' registered successfully.")
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Ollama registration failed: {e.stderr}")


def main():
    parser = argparse.ArgumentParser(
        description="Compress the Byte fused model to lower bit-widths via dequantize → re-quantize.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 compress_model.py                    # 3-bit (recommended)
  python3 compress_model.py --bits 2           # 2-bit (smallest, some quality loss)
  python3 compress_model.py --bits 3 --bits 2  # Try both and compare
        """
    )
    parser.add_argument(
        "--bits", type=int, action="append", default=None,
        choices=[2, 3, 4],
        help="Target quantization bits (default: 3). Can be specified multiple times to try both."
    )
    parser.add_argument(
        "--group-size", type=int, default=64,
        help="Quantization group size (default: 64, matches original model)."
    )
    parser.add_argument(
        "--source", type=str, default=DEFAULT_SOURCE,
        help="Path to the source fused model directory."
    )
    parser.add_argument(
        "--output-dir", type=str, default=None,
        help="Output directory (default: byte_compressed_<bits>bit)."
    )
    parser.add_argument(
        "--register-ollama", action="store_true",
        help="Register the compressed model with Ollama after compression."
    )
    parser.add_argument(
        "--keep-temp", action="store_true",
        help="Keep the temporary dequantized model (useful for debugging)."
    )

    args = parser.parse_args()
    bits_list = args.bits if args.bits else [2]  # Default to 2-bit

    if not os.path.isdir(args.source):
        print(f"❌ Source model not found at: {args.source}")
        print("   Run train_mlx.sh first to create the fused model.")
        sys.exit(1)

    # Ensure mlx_lm is available
    try:
        import mlx_lm  # noqa: F401
    except ImportError:
        print("📦 Installing mlx-lm...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "mlx-lm"])

    try:
        for bits in bits_list:
            output_dir = args.output_dir or os.path.join(SCRIPT_DIR, f"byte_compressed_{bits}bit")
            compressed_dir = compress_model(args.source, bits, args.group_size, output_dir)

            if args.register_ollama:
                model_name = f"byte-llm-{bits}bit"
                register_ollama(compressed_dir, model_name)
    finally:
        if not args.keep_temp:
            cleanup_temp()

    # Print comparison table
    if len(bits_list) > 0:
        print("\n📊 Size Comparison:")
        print(f"  {'Model':<30} {'Size (MB)':>10}")
        print(f"  {'-'*42}")
        source_size = get_model_size_mb(args.source)
        print(f"  {'Original (4-bit)':<30} {source_size:>10.1f}")
        for bits in bits_list:
            d = args.output_dir or os.path.join(SCRIPT_DIR, f"byte_compressed_{bits}bit")
            if os.path.isdir(d):
                sz = get_model_size_mb(d)
                reduction = (1 - sz / source_size) * 100
                print(f"  {f'Compressed ({bits}-bit)':<30} {sz:>10.1f}  ({reduction:+.1f}%)")
        print()


if __name__ == "__main__":
    main()
