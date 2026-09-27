#!/bin/bash
# Train candidate fine-tunes, score each on the app's real prompts, and promote the best
# one only if it beats the live model without losing Mac-command reliability.
#
#   ./training/train_and_select.sh              (2 candidates, seeds 1 and 2)
#   SEEDS="1 2 3" ./training/train_and_select.sh
#
# Why several seeds: one training run can land well or badly by chance (v3 lost Mac
# commands). Picking the best of a few, by test score, is much more reliable.
# Progress: python3 training/watch_training.py training/train_candidate.log

set -euo pipefail
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SEEDS="${SEEDS:-1 2}"
RESULTS="eval_results"
mkdir -p "$RESULTS"

echo "📏 Scoring the live model..."
python3 eval_personalization.py byte-llm --json "$RESULTS/live.json" > "$RESULTS/live.txt"
grep "^Behavior" "$RESULTS/live.txt"

for seed in $SEEDS; do
    dir="adapters_candidate_s$seed"
    echo ""
    echo "🏋️  Training candidate seed=$seed → $dir"
    rm -rf "$dir"
    python3 -m mlx_lm lora -c lora_config_1b.yaml --seed "$seed" --adapter-path "$dir" > train_candidate.log 2>&1
    rm -f "$dir"/0*_adapters.safetensors                       # keep only the final weights

    python3 build_lora_gguf.py "$dir" byte_lora.gguf 2>/dev/null
    ollama create "byte-llm:cand-s$seed" -f ByteModelfile.lora > /dev/null
    echo "📏 Scoring candidate seed=$seed..."
    python3 eval_personalization.py "byte-llm:cand-s$seed" --json "$RESULTS/s$seed.json" > "$RESULTS/s$seed.txt"
    grep "^Behavior" "$RESULTS/s$seed.txt"
done

# Pick the winner: must beat live on behavior, keep 100% style, and not lose commands.
WINNER=$(python3 - "$RESULTS" $SEEDS <<'EOF'
import json, sys
results, seeds = sys.argv[1], sys.argv[2:]
live = json.load(open(f"{results}/live.json"))
best, best_score = None, live["behavior"]
for s in seeds:
    c = json.load(open(f"{results}/s{s}.json"))
    keeps_commands = c["categories"].get("commands", 0) >= live["categories"].get("commands", 0) - 0.08
    if c["behavior"] > best_score and c["style"] >= 0.99 and keeps_commands:
        best, best_score = s, c["behavior"]
    print(f"seed {s}: behavior {c['behavior']:.0%}, style {c['style']:.0%}, "
          f"commands {c['categories'].get('commands', 0):.0%}", file=sys.stderr)
print(f"live:   behavior {live['behavior']:.0%}", file=sys.stderr)
print(best or "")
EOF
)

if [ -n "$WINNER" ]; then
    stamp=$(date +%Y%m%d-%H%M)
    echo ""
    echo "🏆 Promoting seed=$WINNER (backup of the current model: byte-llm:backup-$stamp)"
    ollama cp byte-llm "byte-llm:backup-$stamp" > /dev/null
    ollama cp "byte-llm:cand-s$WINNER" byte-llm > /dev/null
    rm -rf adapters_byte_live_prev && [ -d adapters_byte_v2_live ] && mv adapters_byte_v2_live adapters_byte_live_prev || true
    mv "adapters_candidate_s$WINNER" adapters_byte_v2_live
    echo "   Undo with: ollama cp byte-llm:backup-$stamp byte-llm"
else
    echo ""
    echo "🙅 No candidate beat the live model. Keeping the current one."
fi

# Leave the repo reproducing whatever is live, and free the losers' disk space.
python3 build_lora_gguf.py adapters_byte_v2_live byte_lora.gguf 2>/dev/null
for seed in $SEEDS; do
    ollama rm "byte-llm:cand-s$seed" > /dev/null 2>&1 || true
    rm -rf "adapters_candidate_s$seed"
done
echo "✅ Done. Full reports: training/$RESULTS/"
