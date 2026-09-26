"""Head-to-head of two Ollama models on the prompts the app actually sends.

Usage: python3 compare_models.py byte-llm byte-llm:v2-lora

Each model gets the prompt the app would send it: the fine-tune (detected by its LoRA
adapter, like LocalOllamaProvider.refreshPromptStyle) gets the compact context format
it was trained on; the base model gets the full instruction prompt rebuilt from
DesktopPet/AIEngine.swift.
"""
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (user message, situation, what a good reply must do)
CASES = [
    ("hey byte, how's it going?", {}, {}),
    ("open chrome please", {}, {"cmd": r"open -a \"?(Google )?Chrome"}),
    ("can you turn the volume down", {}, {"cmd": r"osascript -e .*volume"}),
    ("ugh this build keeps failing", {}, {}),
    ("what music do I like?", {}, {"mentions": r"arijit"}),
    ("I finally fixed the bug!", {}, {}),
    ("do you remember my name?", {}, {"mentions": r"pratik"}),
    ("tell me something fun", {}, {}),
    ("what song is this?", {"playing": ("Kesariya", "Arijit Singh")}, {"mentions": r"kesariya|arijit"}),
    ("hey byte", {"focus": "deep work"}, {"brief": 10}),
    ("mute please", {"focus": "on a call"}, {"cmd": r"muted true", "brief": 6}),
]
MEMORY = ["they listen to Arijit Singh", "they are working on the DesktopPet companion application"]
TAGS = re.compile(r"\[ACTION:\s*\w+\]\s*\[EMOTION:\s*\w+\]")
CMD = re.compile(r"\[CMD:\s*([^\]]+)\]")


def static_prompt() -> str:
    src = open(os.path.join(ROOT, "DesktopPet/AIEngine.swift")).read()
    i = src.index("            ACTION DESCRIPTIONS:")
    j = src.index("            ENVIRONMENT CONTEXT: \\(context)", i)
    head = ("You are an autonomous male AI desktop pet named Byte (he/him). You must decide your "
            "next physical action and what you want to say.\nPERSONALITY TRAIT: Playful and witty.\n\n")
    return head + re.sub(r"^ {12}", "", src[i:j], flags=re.M)


def build_full(static: str, msg: str, sit: dict) -> str:
    extra = ""
    if "playing" in sit:
        extra += f"NOW PLAYING: '{sit['playing'][0]}' by {sit['playing'][1]}\n"
    if "focus" in sit:
        extra += f"USER FOCUS: {sit['focus']}\n"
    return static + (
        "ENVIRONMENT CONTEXT: afternoon\n"
        "DEVELOPER WORKSPACE: IDE/App: Xcode, File: PetScene.swift, Language: Swift\n" + extra +
        "ABOUT THE USER: Their name is Pratik. Use it now and then, like a friend would, not in every line. "
        "What you know about them: " + "; ".join(m[0].upper() + m[1:] for m in MEMORY) + ".\n"
        "YOUR CURRENT EMOTION: normal. Calm and steady.\n"
        "AVAILABLE ACTIONS: idle, wander, sleep, jump, sit, spin, dance, sitOnCorner, wave, stretch\n"
        "*** PRIORITY USER DIRECTIVE ***\n"
        f'USER SPOKE TO YOU: "{msg}"\n'
        f'THE USER SAID: "{msg}". Answer them naturally, directly, and warmly.\n')


def build_compact(msg: str, sit: dict) -> str:
    """Same shape as CompactPrompt.build() in DesktopPet/AIEngine.swift."""
    tags = ["[USER PROFILE: name=Pratik]", "[WORKSPACE: Xcode active, PetScene.swift]"]
    if "focus" in sit:
        tags.append(f"[FOCUS: {sit['focus']}]")
    if "playing" in sit:
        tags.append(f"[NOW PLAYING: '{sit['playing'][0]}' by {sit['playing'][1]}]")
    # Same relevance rule as MemoryGraph.compactMemory(): music facts only when music is
    # playing or being talked about.
    about_music = "playing" in sit or any(w in msg.lower() for w in ("music", "song", "listen", "artist"))
    memory = [m for m in MEMORY if about_music or "listen" not in m]
    if memory:
        tags.append("[MEMORY: " + "; ".join(memory) + "]")
    return "User: " + " ".join(tags) + f' | User: "{msg}"'


def is_fine_tune(model: str) -> bool:
    req = urllib.request.Request("http://localhost:11434/api/show", json.dumps({"model": model}).encode(),
                                 {"Content-Type": "application/json"})
    # An attached LoRA adapter, not the chat template (the base model inherits one too).
    return "\nADAPTER " in json.load(urllib.request.urlopen(req)).get("modelfile", "")


def ask(model: str, prompt: str) -> tuple:
    body = {"model": model, "prompt": prompt, "stream": False, "keep_alive": "30m",
            "options": {"temperature": 0.3, "num_predict": 60, "seed": 1}}
    req = urllib.request.Request("http://localhost:11434/api/generate", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    start = time.time()
    out = json.load(urllib.request.urlopen(req))["response"].strip().replace("\n", " ")
    return out, time.time() - start


def main() -> None:
    models = sys.argv[1:] or ["byte-llm", "byte-llm:v2-lora"]
    static = static_prompt()
    totals = {}
    for model in models:
        compact = is_fine_tune(model)
        build = (lambda m, sit: build_compact(m, sit)) if compact else (lambda m, sit: build_full(static, m, sit))
        ask(model, build("hi", {}))  # warm up + prime prompt cache
        points, possible, latency = 0, 0, 0.0
        print(f"\n===== {model} ({'compact prompt' if compact else 'full instruction prompt'})")
        for msg, sit, want in CASES:
            out, secs = ask(model, build(msg, sit))
            latency += secs
            checks = [("tags", bool(TAGS.search(out))),
                      ("clean", not out.upper().startswith("RESPONSE:"))]
            if "cmd" in want:
                m = CMD.search(out)
                checks.append(("cmd", bool(m and re.search(want["cmd"], m.group(1), re.I))))
            if "mentions" in want:
                checks.append(("memory", bool(re.search(want["mentions"], out, re.I))))
            if "brief" in want:
                speech = re.sub(r"\[[^\]]*\]", "", out).strip()
                checks.append(("brief", len(speech.split()) <= want["brief"]))
            got = sum(ok for _, ok in checks)
            points += got
            possible += len(checks)
            marks = " ".join(f"{name}{'✓' if ok else '✗'}" for name, ok in checks)
            print(f"  [{marks}] {msg:30s} → {out[:100]}")
        totals[model] = (points, possible, latency / len(CASES))
    print()
    for model, (p, n, lat) in totals.items():
        print(f"{model:22s} score {p}/{n}   avg reply {lat:.2f}s")


if __name__ == "__main__":
    main()
