#!/usr/bin/env python3
"""
Fix training data: Add [CMD: none] tag to samples missing it.

The model needs to consistently learn the 3-tag format:
  [ACTION: xxx] [EMOTION: xxx] [CMD: none] speech text

Without this, ~28% of training samples teach the model to skip the CMD tag,
causing the streaming parser to fail and leak CMD instructions into TTS.
"""
import json
import re
import sys
import os

INPUT_FILE = "train.jsonl"
OUTPUT_FILE = "train_fixed.jsonl"

# Pattern: [ACTION: xxx] [EMOTION: xxx] followed by speech (no CMD tag)
# We'll insert [CMD: none] after [EMOTION: xxx]
ACTION_EMOTION_PATTERN = re.compile(
    r'(\[ACTION:\s*\w+\]\s*\[EMOTION:\s*\w+\])\s*(?!\[CMD:)'
)

fixed_count = 0
total_count = 0
error_count = 0

with open(INPUT_FILE, 'r') as fin, open(OUTPUT_FILE, 'w') as fout:
    for line_num, line in enumerate(fin, 1):
        line = line.strip()
        if not line:
            continue
        total_count += 1
        
        try:
            obj = json.loads(line)
            assistant_content = obj['messages'][1]['content']
            
            if '[CMD:' not in assistant_content:
                # Insert [CMD: none] after [EMOTION: xxx]
                new_content = ACTION_EMOTION_PATTERN.sub(r'\1 [CMD: none] ', assistant_content)
                if new_content != assistant_content:
                    fixed_count += 1
                obj['messages'][1]['content'] = new_content
            
            fout.write(json.dumps(obj, ensure_ascii=False) + '\n')
        except Exception as e:
            error_count += 1
            if error_count <= 5:
                print(f"Warning: Error on line {line_num}: {e}", file=sys.stderr)
            # Write the original line on error
            fout.write(line + '\n')

print(f"Total samples: {total_count}")
print(f"Fixed (added [CMD: none]): {fixed_count}")
print(f"Errors: {error_count}")
print(f"Output written to: {OUTPUT_FILE}")

# Also fix test.jsonl and valid.jsonl if they exist
for split_file in ["test.jsonl", "valid.jsonl"]:
    if os.path.exists(split_file):
        split_fixed = 0
        split_total = 0
        out_name = split_file.replace('.jsonl', '_fixed.jsonl')
        with open(split_file, 'r') as fin, open(out_name, 'w') as fout:
            for line in fin:
                line = line.strip()
                if not line:
                    continue
                split_total += 1
                try:
                    obj = json.loads(line)
                    assistant_content = obj['messages'][1]['content']
                    if '[CMD:' not in assistant_content:
                        new_content = ACTION_EMOTION_PATTERN.sub(r'\1 [CMD: none] ', assistant_content)
                        if new_content != assistant_content:
                            split_fixed += 1
                        obj['messages'][1]['content'] = new_content
                    fout.write(json.dumps(obj, ensure_ascii=False) + '\n')
                except:
                    fout.write(line + '\n')
        print(f"{split_file}: Fixed {split_fixed}/{split_total}")
