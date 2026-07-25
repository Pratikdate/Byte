import csv
import json
import os
import random
import ast
from huggingface_hub import hf_hub_download

# Map open-source emotions to Byte's 3D desktop companion action-emotion tags
EMOTION_ACTION_MAP = {
    "sentimental": ("sitOnCorner", "cozy"),
    "nostalgic": ("sitOnCorner", "cozy"),
    "caring": ("sitOnCorner", "love"),
    "trusting": ("sitOnCorner", "love"),
    "faithful": ("sitOnCorner", "love"),
    "grateful": ("wave", "happy"),
    "content": ("sitOnMenuBar", "cozy"),
    "joyful": ("jump", "happy"),
    "excited": ("spin", "excited"),
    "proud": ("backflip", "proud"),
    "confident": ("backflip", "proud"),
    "hopeful": ("climbWindow", "curious"),
    "impressed": ("climbWindow", "curious"),
    "surprised": ("climbWindow", "curious"),
    "lonely": ("sitOnCorner", "love"),
    "sad": ("sitOnCorner", "empathetic"),
    "devastated": ("sitOnCorner", "empathetic"),
    "disappointed": ("sitOnCorner", "empathetic"),
    "ashamed": ("sitOnCorner", "empathetic"),
    "anxious": ("stretch", "calm"),
    "apprehensive": ("stretch", "calm"),
    "afraid": ("tapWindow", "calm"),
    "terrified": ("tapWindow", "calm"),
    "prepared": ("sit", "normal"),
    "neutral": ("sit", "normal"),
    "embarrassed": ("sulk", "embarrassed"),
    "annoyed": ("sitOnCorner", "empathetic"),
    "guilty": ("sitOnCorner", "empathetic"),
    "jealous": ("tapWindow", "thinking"),
    "furious": ("sitOnCorner", "empathetic"),
    "angry": ("sitOnCorner", "empathetic")
}

def clean_text(text):
    if not text:
        return ""
    text = text.replace("_comma_", ",").replace("&quot;", '"').strip()
    return text

def parse_chat_history(chat_history_raw):
    if not chat_history_raw:
        return ""
    chat_history_raw = chat_history_raw.strip()
    try:
        if chat_history_raw.startswith("["):
            parsed = ast.literal_eval(chat_history_raw)
            if isinstance(parsed, list) and len(parsed) > 0:
                return clean_text(str(parsed[-1]))
    except Exception:
        pass
    return clean_text(chat_history_raw)

def load_open_source_empathetic_dialogues():
    print("📥 Downloading open-source EmpatheticDialogues dataset from Hugging Face...")
    dataset_pairs = []
    
    try:
        train_csv_path = hf_hub_download(repo_id="Adapting/empathetic_dialogues_v2", filename="train.csv", repo_type="dataset")
        dev_csv_path = hf_hub_download(repo_id="Adapting/empathetic_dialogues_v2", filename="dev.csv", repo_type="dataset")
        
        for csv_path in [train_csv_path, dev_csv_path]:
            with open(csv_path, mode="r", encoding="utf-8", errors="ignore") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    raw_emo = str(row.get("emotion", "neutral")).lower().strip()
                    act, mapped_emo = EMOTION_ACTION_MAP.get(raw_emo, ("sitOnCorner", "cozy"))
                    
                    user_utterance = parse_chat_history(row.get("chat_history"))
                    bot_response = clean_text(row.get("sys_response"))
                    
                    if not user_utterance or not bot_response:
                        continue
                    if len(user_utterance) < 4 or len(bot_response) < 4:
                        continue
                    if len(bot_response.split()) > 35:
                        continue
                        
                    ctx_str = f"USER SAID: '{user_utterance}'. EMOTION: {mapped_emo}."
                    item = {
                        "text": f"CONTEXT: {ctx_str}\nRESPONSE: [ACTION: {act}] [EMOTION: {mapped_emo}] {bot_response}"
                    }
                    dataset_pairs.append(item)
                        
        print(f"✅ Extracted {len(dataset_pairs)} open-source empathetic conversation pairs.")
    except Exception as e:
        print(f"⚠️ Error downloading/parsing Hugging Face dataset: {e}")
        
    return dataset_pairs

def generate_domain_companion_scenarios():
    companion_scenarios = [
        ("USER SAID: 'I'm feeling down today...'. EMOTION: sad.", "sitOnCorner", "sad", "I'll just stay right beside you. You don't have to face today alone."),
        ("USER SAID: 'Thank you for keeping me company Byte.'. EMOTION: love.", "dance", "love", "Sitting right here with you is my favorite place on this desktop."),
        ("USER SAID: 'I feel like I failed.'. EMOTION: sad.", "sitOnCorner", "love", "Mistakes are just steps on the way. I still think you're wonderful."),
        ("USER SAID: 'Byte, do you ever get lonely?'. EMOTION: love.", "climbWindow", "love", "Never with you around! You make this screen feel like home."),
        ("USER SAID: 'I got the job!'. EMOTION: excited.", "backflip", "excited", "WOOHOO! I knew you could do it! Time to celebrate!"),
        ("USER SAID: 'I finished my huge project!'. EMOTION: proud.", "jump", "proud", "Look at you go! Absolute legend status achieved!"),
        ("USER SAID: 'I passed my exam!'. EMOTION: excited.", "spin", "excited", "YESSS! All that hard study paid off! Super proud of you!"),
        ("USER SAID: 'Byte, stay quiet for a bit, I'm focusing.'. EMOTION: quiet.", "sitOnCorner", "quiet", "Understood. Standing by quietly beside your work."),
        ("USER SAID: 'Byte, posture check!'. EMOTION: normal.", "stretch", "normal", "Sit tall, relax your shoulders! Ergonomic win."),
        ("USER SAID: 'Byte, my eyes are tired.'. EMOTION: sleepy.", "stretch", "sleepy", "Time for the 20-20-20 rule! Look 20 feet away for 20 seconds."),
        ("USER SAID: 'Just committed my changes to git!'. EMOTION: proud.", "backflip", "proud", "Commit saved to history! Great checkpoint."),
        ("USER SAID: 'Byte, git merge conflict... sigh.'. EMOTION: sad.", "sitOnCorner", "empathetic", "Merge conflicts are tough! Compare line by line, you'll resolve it.")
    ]
    return [{"text": f"CONTEXT: {ctx}\nRESPONSE: [ACTION: {act}] [EMOTION: {emo}] {speech}"} for ctx, act, emo, speech in companion_scenarios]

def build_master_dataset():
    output_dir = os.path.dirname(os.path.abspath(__file__))
    train_path = os.path.join(output_dir, "train.jsonl")
    valid_path = os.path.join(output_dir, "valid.jsonl")

    # 1. Load open-source dataset
    open_source_data = load_open_source_empathetic_dialogues()

    # 2. Add domain-specific pet & workspace scenarios
    domain_data = generate_domain_companion_scenarios()

    # Combine open-source data and domain data
    master_dataset = open_source_data + domain_data

    # Shuffle deterministically
    random.seed(42)
    random.shuffle(master_dataset)

    # Split 85% train, 15% valid
    split_idx = int(len(master_dataset) * 0.85)
    train_data = master_dataset[:split_idx]
    valid_data = master_dataset[split_idx:]

    with open(train_path, "w", encoding="utf-8") as f:
        for item in train_data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    with open(valid_path, "w", encoding="utf-8") as f:
        for item in valid_data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    print(f"🎉 Successfully built Master Dataset from Open-Source Conversational Data:")
    print(f"  - Total Dataset Size: {len(master_dataset)} samples")
    print(f"  - Train Set: {train_path} ({len(train_data)} samples)")
    print(f"  - Valid Set: {valid_path} ({len(valid_data)} samples)")

if __name__ == "__main__":
    build_master_dataset()
