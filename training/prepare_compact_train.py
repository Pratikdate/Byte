"""
Prepare Chat Messages Dataset Split for MLX Loss-Masked Fine-Tuning
"""

import json
import os
import random

def prepare_data():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    train_file = os.path.join(script_dir, "train.jsonl")
    valid_file = os.path.join(script_dir, "valid.jsonl")
    test_file = os.path.join(script_dir, "test.jsonl")

    print(f"📖 Reading raw dataset from {train_file}...")
    records = []
    with open(train_file, "r", encoding="utf-8", errors="ignore") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                text = ""
                if "text" in obj:
                    text = obj["text"]
                elif "prompt" in obj and "completion" in obj:
                    text = f"{obj['prompt']}{obj['completion']}"
                elif "messages" in obj:
                    user_msg = next((m["content"] for m in obj["messages"] if m["role"] == "user"), "")
                    asst_msg = next((m["content"] for m in obj["messages"] if m["role"] == "assistant"), "")
                    text = f"CONTEXT: {user_msg}\nRESPONSE: {asst_msg}"

                if "RESPONSE:" in text:
                    parts = text.split("RESPONSE:", 1)
                    user_content = parts[0].replace("CONTEXT:", "").strip()
                    asst_content = parts[1].strip()
                    
                    records.append({
                        "messages": [
                            {"role": "user", "content": f"CONTEXT: {user_content}"},
                            {"role": "assistant", "content": asst_content}
                        ]
                    })
            except Exception as e:
                continue

    total = len(records)
    print(f"✅ Loaded and formatted {total} chat messages records.")

    # Shuffle deterministically
    random.seed(42)
    random.shuffle(records)

    # 90% train, 5% valid, 5% test (max 2000 each for validation & test)
    val_size = min(2000, max(200, int(total * 0.05)))
    test_size = min(2000, max(200, int(total * 0.05)))
    
    test_data = records[:test_size]
    valid_data = records[test_size:test_size + val_size]
    train_data = records[test_size + val_size:]

    print(f"💾 Saving train.jsonl ({len(train_data)}), valid.jsonl ({len(valid_data)}), test.jsonl ({len(test_data)})...")
    
    with open(train_file, "w", encoding="utf-8") as f:
        for item in train_data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    with open(valid_file, "w", encoding="utf-8") as f:
        for item in valid_data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    with open(test_file, "w", encoding="utf-8") as f:
        for item in test_data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    print("🎉 Chat messages dataset formatting and 3-way split complete!")

if __name__ == "__main__":
    prepare_data()
