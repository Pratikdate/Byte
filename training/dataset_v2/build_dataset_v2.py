"""Builds Byte's v2 fine-tuning dataset: training/data_v2/{train,valid}.jsonl.

  1. Clean the original data: validate every reply against the app (actions, emotions,
     allowed Mac commands), drop exact duplicates, and cap any single reply line at 2 uses
     so the model doesn't learn a handful of stock phrases.
  2. Add the hand-written examples from curated.py, expanded across varied contexts.
  3. Split 90/10 per category so every behavior is represented in validation.

Usage: python3 build_dataset_v2.py
"""
import collections
import json
import os
import random

from curated import ARTISTS, CASES, EDITORS, NAMES, PROJECTS
from validate import check_reply

HERE = os.path.dirname(os.path.abspath(__file__))
TRAINING = os.path.dirname(HERE)
MAX_REPEATS_PER_REPLY = 2         # original data: curb stock phrases
MAX_REPEATS_CURATED = 6           # curated: the same good line across different contexts is the point
CURATED_WEIGHT = 2                # contexts per reply = case["n"] * CURATED_WEIGHT
MINUTES = [26, 34, 45, 52, 68, 90]


def row(user: str, reply: str, category: str) -> dict:
    return {"messages": [{"role": "user", "content": user},
                         {"role": "assistant", "content": reply}], "_cat": category}


def load_original() -> tuple:
    rows, rejected = [], collections.Counter()
    for name in ("train.jsonl", "valid.jsonl"):
        for line in open(os.path.join(TRAINING, name)):
            r = json.loads(line)
            user = r["messages"][0]["content"].strip()
            reply = " ".join(r["messages"][1]["content"].split())
            why = check_reply(reply)
            if why:
                rejected[why.split(":")[0]] += 1
                continue
            rows.append(row(user, reply, "original"))
    return rows, rejected


def dedupe(rows: list, max_repeats: int = MAX_REPEATS_PER_REPLY) -> list:
    seen_pairs, reply_uses, out = set(), collections.Counter(), []
    for r in rows:
        user, reply = r["messages"][0]["content"], r["messages"][1]["content"]
        speech = reply.split("] ", 3)[-1].lower()
        if (user, reply) in seen_pairs or reply_uses[speech] >= max_repeats:
            continue
        seen_pairs.add((user, reply))
        reply_uses[speech] += 1
        out.append(r)
    return out


def expand_curated(rng: random.Random) -> list:
    out = []
    for case in CASES:
        for reply_template in case["replies"]:
            for _ in range(case["n"] * CURATED_WEIGHT):
                artist = rng.choice(list(ARTISTS))
                editor, file, lang = rng.choice(EDITORS)
                slots = dict(name=rng.choice(NAMES), artist=artist, track=rng.choice(ARTISTS[artist]),
                             project=rng.choice(PROJECTS), editor=editor, file=file, lang=lang,
                             minutes=rng.choice(MINUTES))
                ctx = case["ctx"].format(**slots)
                phrasing = rng.choice(case["user"]) if isinstance(case["user"], list) else case["user"]
                user_words = phrasing.format(**slots) if phrasing else None
                prompt = "CONTEXT: User: " + " ".join(p for p in [
                    ctx, f'| User: "{user_words}"' if user_words else ""] if p).strip()
                reply = reply_template.format(**slots).rstrip()
                why = check_reply(reply)
                assert not why, f"curated reply fails validation ({why}): {reply}"
                out.append(row(prompt, reply, case["cat"]))
    return out


def split(rows: list, rng: random.Random) -> tuple:
    by_cat = collections.defaultdict(list)
    for r in rows:
        by_cat[r["_cat"]].append(r)
    train, valid = [], []
    for cat_rows in by_cat.values():
        rng.shuffle(cat_rows)
        cut = max(1, len(cat_rows) // 10)
        valid += cat_rows[:cut]
        train += cat_rows[cut:]
    rng.shuffle(train)
    rng.shuffle(valid)
    return train, valid


def write(path: str, rows: list) -> None:
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps({"messages": r["messages"]}, ensure_ascii=False) + "\n")


def main() -> None:
    rng = random.Random(42)
    original, rejected = load_original()
    cleaned = dedupe(original)
    curated = dedupe(expand_curated(rng), MAX_REPEATS_CURATED)
    train, valid = split(cleaned + curated, rng)

    out_dir = os.path.join(TRAINING, "data_v2")    # mlx_lm expects train.jsonl/valid.jsonl in one folder
    os.makedirs(out_dir, exist_ok=True)
    write(os.path.join(out_dir, "train.jsonl"), train)
    write(os.path.join(out_dir, "valid.jsonl"), valid)

    cats = collections.Counter(r["_cat"] for r in train + valid)
    print(f"original: {len(original) + sum(rejected.values())} rows, rejected {dict(rejected)}, "
          f"{len(original) - len(cleaned)} duplicates removed -> {len(cleaned)}")
    print(f"curated:  {len(curated)} rows across {len(cats) - 1} behaviors: "
          + ", ".join(f"{c}={n}" for c, n in cats.most_common() if c != "original"))
    print(f"wrote data_v2/train.jsonl ({len(train)}) and data_v2/valid.jsonl ({len(valid)})")


if __name__ == "__main__":
    main()
