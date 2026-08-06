"""
Quantitative Evaluation Harness for Byte LLM
Scores schema validity, CMD accuracy, CMD false-positive rate, and speech completeness.

Usage:
    python3 eval_model.py                          # Evaluate default byte-llm
    python3 eval_model.py --model byte-llm-3bit    # Evaluate compressed model
    python3 eval_model.py --compare                # Side-by-side comparison
"""

import argparse
import json
import os
import re
import urllib.request
import time

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "byte-llm"  # Default, overridden by --model

# Regex patterns for validation
SCHEMA_REGEX = re.compile(
    r"^\[ACTION:\s*([a-zA-Z0-9_-]+)\]\s*\[EMOTION:\s*([a-zA-Z0-9_-]+)\]\s*\[CMD:\s*(.*?)\]\s*(.*)$",
    re.DOTALL
)

SYSTEM_CMD_KEYWORDS = [
    "volume", "music", "spotify", "terminal", "finder", "dark mode",
    "light mode", "screenshot", "mute", "unmute", "battery", "cpu", "storage", "sleep mac"
]

def query_model(prompt_text):
    payload = json.dumps({
        "model": MODEL_NAME,
        "prompt": prompt_text,
        "stream": False,
        "options": {
            "temperature": 0.2
        }
    }).encode("utf-8")
    
    req = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("response", "").strip()
    except Exception as e:
        print(f"Error querying model: {e}")
        return ""

def evaluate(model_name=None):
    """Run evaluation on a single model. Returns a results dict."""
    global MODEL_NAME
    if model_name:
        MODEL_NAME = model_name

    script_dir = os.path.dirname(os.path.abspath(__file__))
    test_file = os.path.join(script_dir, "test.jsonl")

    if not os.path.exists(test_file):
        print(f"❌ Test file not found at {test_file}. Run prepare_compact_train.py first.")
        return None

    print(f"\n📖 Loading evaluation dataset from {test_file}...")
    print(f"🤖 Model: {MODEL_NAME}")
    samples = []
    with open(test_file, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                samples.append(json.loads(line))

    test_samples = samples[:100]
    total = len(test_samples)
    print(f"⚡ Running quantitative evaluation on {total} held-out test samples...\n")

    valid_schema_count = 0
    non_sys_count = 0
    false_pos_cmd_count = 0
    sys_cmd_count = 0
    correct_sys_cmd_count = 0
    speech_present_count = 0

    start_time = time.time()

    for idx, item in enumerate(test_samples, 1):
        if "messages" in item:
            prompt = next((m["content"] for m in item["messages"] if m["role"] == "user"), "")
        else:
            prompt = item.get("prompt", "")

        response = query_model(prompt)
        match = SCHEMA_REGEX.match(response)

        if match:
            valid_schema_count += 1
            action, emotion, cmd, speech = match.groups()
            
            if speech.strip():
                speech_present_count += 1

            prompt_lower = prompt.lower()
            is_system_query = any(kw in prompt_lower for kw in SYSTEM_CMD_KEYWORDS)

            if not is_system_query:
                non_sys_count += 1
                if cmd.strip().lower() != "none":
                    false_pos_cmd_count += 1
            else:
                sys_cmd_count += 1
                if cmd.strip().lower() != "none" and ("osascript" in cmd or "open -a" in cmd or "screencapture" in cmd or "pmset" in cmd):
                    correct_sys_cmd_count += 1

        print(f"[{idx}/{total}] Prompt: {prompt[:35]}... -> Response: {response[:60]}...")

    elapsed = time.time() - start_time

    schema_acc = (valid_schema_count / total) * 100
    speech_rate = (speech_present_count / total) * 100
    false_pos_rate = (false_pos_cmd_count / max(1, non_sys_count)) * 100
    sys_cmd_acc = (correct_sys_cmd_count / max(1, sys_cmd_count)) * 100

    results = {
        "model": MODEL_NAME,
        "total": total,
        "elapsed": elapsed,
        "schema_acc": schema_acc,
        "speech_rate": speech_rate,
        "false_pos_rate": false_pos_rate,
        "sys_cmd_acc": sys_cmd_acc,
    }

    print("\n" + "=" * 60)
    print(f"📊 QUANTITATIVE EVALUATION RESULTS — {MODEL_NAME}")
    print("=" * 60)
    print(f"Total Samples Evaluated  : {total}")
    print(f"Evaluation Duration      : {elapsed:.2f}s ({elapsed/total:.2f}s / sample)")
    print(f"Schema Validity Rate     : {schema_acc:.1f}%")
    print(f"Speech Presence Rate     : {speech_rate:.1f}%")
    print(f"CMD False Positive Rate  : {false_pos_rate:.1f}%  (Target: 0.0%)")
    print(f"CMD System Accuracy Rate : {sys_cmd_acc:.1f}%")
    print("=" * 60)

    return results


def compare_models(models):
    """Run evaluation on multiple models and print side-by-side comparison."""
    all_results = []
    for model in models:
        result = evaluate(model_name=model)
        if result:
            all_results.append(result)

    if len(all_results) < 2:
        print("\n⚠️  Need at least 2 models to compare.")
        return

    print("\n" + "=" * 70)
    print("📊 SIDE-BY-SIDE MODEL COMPARISON")
    print("=" * 70)

    # Header
    header = f"{'Metric':<28}"
    for r in all_results:
        header += f" {r['model']:>18}"
    print(header)
    print("-" * 70)

    metrics = [
        ("Schema Validity Rate", "schema_acc", "%"),
        ("Speech Presence Rate", "speech_rate", "%"),
        ("CMD False Positive Rate", "false_pos_rate", "%"),
        ("CMD System Accuracy", "sys_cmd_acc", "%"),
        ("Avg Latency (s/sample)", "elapsed", "s"),
    ]

    for label, key, unit in metrics:
        row = f"{label:<28}"
        for r in all_results:
            val = r[key]
            if key == "elapsed":
                val = val / r["total"]
            row += f" {val:>17.1f}{unit}"
        print(row)

    print("=" * 70)

    # Highlight winner
    best_schema = max(all_results, key=lambda r: r["schema_acc"])
    print(f"\n🏆 Best Schema Accuracy: {best_schema['model']} ({best_schema['schema_acc']:.1f}%)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Evaluate Byte LLM models via Ollama.")
    parser.add_argument(
        "--model", type=str, default="byte-llm",
        help="Ollama model name to evaluate (default: byte-llm)."
    )
    parser.add_argument(
        "--compare", action="store_true",
        help="Compare original (byte-llm) with compressed model (byte-llm-3bit)."
    )
    parser.add_argument(
        "--models", nargs="+", default=None,
        help="List of model names to compare (e.g., --models byte-llm byte-llm-3bit byte-llm-2bit)."
    )
    args = parser.parse_args()

    if args.compare:
        models = args.models or ["byte-llm", "byte-llm-3bit"]
        compare_models(models)
    else:
        evaluate(model_name=args.model)

