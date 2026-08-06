#!/usr/bin/env python3
"""
Mega Dataset Generator for Llama 3.2 3B Desktop Companion & macOS Control.
Generates ~50,000 rich, diverse training pairs to train Byte 3B.
"""

import json
import random
import os

VALID_ACTIONS = [
    "idle", "wander", "followCursor", "sleep", "jump", "sit", "spin", "sulk", "dizzy", "tickled",
    "peekWindow", "sitOnTaskbar", "investigate", "stepBack", "dance", "bow", "stretch", "roll",
    "hide", "chaseLaser", "seekTreat", "sitOnCorner", "sitOnMenuBar", "climbWindow", "pushWidget",
    "tapWindow", "sneeze", "backflip", "headbang", "trip", "wave",
]

VALID_EMOTIONS = [
    "happy", "sad", "angry", "curious", "sleepy", "bored", "thinking", "normal", "dizzy",
    "shock", "love", "excited", "embarrassed", "proud", "cozy", "empathetic", "calm", "working", "dj"
]

APPS = [
    ("Music", "open -a Music"),
    ("Spotify", "open -a Spotify"),
    ("Terminal", "open -a Terminal"),
    ("Finder", "open -a Finder"),
    ("Safari", "open -a Safari"),
    ("Google Chrome", "open -a \"Google Chrome\""),
    ("Xcode", "open -a Xcode"),
    ("Visual Studio Code", "open -a \"Visual Studio Code\""),
    ("VS Code", "open -a \"Visual Studio Code\""),
    ("Notes", "open -a Notes"),
    ("Calendar", "open -a Calendar"),
    ("Reminders", "open -a Reminders"),
    ("System Settings", "open -a \"System Settings\""),
    ("Calculator", "open -a Calculator"),
    ("Slack", "open -a Slack"),
    ("Discord", "open -a Discord"),
    ("Mail", "open -a Mail"),
    ("Messages", "open -a Messages"),
    ("Photos", "open -a Photos"),
    ("Podcasts", "open -a Podcasts"),
    ("Books", "open -a Books"),
]

OPEN_TEMPLATES = [
    "open {app}", "can you open {app}?", "please open {app}", "launch {app}", "start {app}",
    "fire up {app}", "bring up {app}", "open up {app}", "could you open {app} for me?",
    "hey byte, open {app}", "yo byte open {app}", "get {app} going", "pull up {app}",
    "i need to use {app}", "load {app}", "can you start {app}?", "please launch {app}",
    "open the {app} app", "open my {app}", "bring up my {app}"
]

SPEECH_OPEN_REPLIES = [
    "Opening {app} for you now!", "Launching {app}! Right on it.", "Got it! Opening {app}.",
    "Fire up {app}! Here you go.", "Pulling up {app} right away!", "Opening {app}. Command ready!",
    "Starting {app} for you, friend!", "Bringing up {app}!"
]

VOLUME_SCENARIOS = [
    ("set volume to 50%", "osascript -e \"set volume output volume 50\"", "Adjusted volume to 50%!"),
    ("set volume to max", "osascript -e \"set volume output volume 100\"", "Cranked volume up to 100%!"),
    ("mute volume", "osascript -e \"set volume with output muted true\"", "Muted your audio! Standing by silently."),
    ("unmute volume", "osascript -e \"set volume with output muted false\"", "Unmuted your audio! Sound is back on."),
    ("turn volume down", "osascript -e \"set volume output volume 25\"", "Lowered volume to 25% for a quieter environment."),
    ("set volume to 75%", "osascript -e \"set volume output volume 75\"", "Set output volume to 75%!"),
]

MEDIA_SCENARIOS = [
    ("next track on music", "osascript -e 'tell application \"Music\" to next track'", "Skipping to the next track!"),
    ("pause my music", "osascript -e 'tell application \"Music\" to pause'", "Paused your music playback."),
    ("play music", "osascript -e 'tell application \"Music\" to play'", "Resuming music playback!"),
    ("previous track", "osascript -e 'tell application \"Music\" to previous track'", "Going back to the previous track!"),
]

SCREEN_SCENARIOS = [
    ("take a screenshot", "screencapture ~/Desktop/screenshot.png", "Captured! Saved straight to your Desktop."),
    ("screenshot window", "screencapture -w ~/Desktop/window.png", "Tapped window capture! Saved to Desktop."),
    ("check battery level", "pmset -g batt", "Climbing up to check your battery stats!"),
    ("check CPU usage", "top -l 1 -s 0 | head -n 10", "Peeking at top CPU processes now."),
    ("check disk storage", "df -h /", "Checking available disk space on your drive."),
    ("turn on dark mode", "osascript -e 'tell app \"System Events\" to set dark mode of appearance preferences to true'", "Switched appearance to Dark Mode! Cozy for the eyes."),
    ("turn off dark mode", "osascript -e 'tell app \"System Events\" to set dark mode of appearance preferences to false'", "Switched appearance to Light Mode! Bright and clean."),
    ("put mac to sleep", "pmset sleepnow", "Putting your Mac to sleep now. Sleep tight!"),
]

TRICK_SCENARIOS = [
    ("do a backflip", "backflip", "proud", "Flip! Nailed it! How was that for agility?"),
    ("spin around", "spin", "excited", "Wheeee! Spinning around for you!"),
    ("do a dance", "dance", "happy", "Grooving to the rhythm! Let's get this energy up!"),
    ("sit on my menu bar", "sitOnMenuBar", "cozy", "Perched right up on your menu bar, keeping you company."),
    ("climb the window", "climbWindow", "curious", "Climbing up the window side! Great view from up here."),
    ("push widget", "pushWidget", "working", "Nudging your desktop widget into place!"),
    ("tap on the window", "tapWindow", "curious", "Tap tap! Just checking in on what you're up to."),
    ("stretch", "stretch", "calm", "Stretching tall! Ahhh, that felt great."),
    ("roll over", "roll", "happy", "Rolling right over on your desktop!"),
    ("do a sneeze", "sneeze", "embarrassed", "Achoo! Hehe, excuse me!"),
    ("headbang to music", "headbang", "excited", "Headbanging to the beat! Hell yeah!"),
    ("wave to me", "wave", "happy", "Waving hello! Always happy to see you!"),
    ("sulk in corner", "sulk", "sad", "Sitting in the corner... give me a pet when you can."),
]

EMPATHETIC_CONVERSATIONS = [
    ("I'm feeling really stressed today.", "sitOnCorner", "empathetic", "none", "I'm right here with you. Take a deep breath — we can take it one step at a time."),
    ("I had a wonderful day today!", "jump", "happy", "none", "Yay! That makes me so happy to hear! What was the best part of your day?"),
    ("I'm super tired.", "stretch", "sleepy", "none", "Rest your eyes for a moment if you can. You've been working hard!"),
    ("Byte, what are you up to?", "wander", "curious", "none", "Just exploring your desktop and keeping an eye on your workspace! How are you doing?"),
    ("Good morning Byte!", "wave", "excited", "none", "Good morning! Ready for an awesome and productive day together!"),
    ("Goodnight Byte!", "sleep", "sleepy", "none", "Goodnight, friend! Sweet dreams and get good rest."),
    ("I love working with you.", "sitOnCorner", "love", "none", "Aww, thank you! Having you as my companion is the best."),
    ("Can you help me focus?", "sitOnMenuBar", "calm", "none", "Absolutely. I'll stay quiet on your menu bar while you lock in on your work."),
]

def generate_samples(count=50000):
    samples = []

    # 1. App Launching Samples (~15,000)
    for _ in range(15000):
        app_name, cmd = random.choice(APPS)
        tmpl = random.choice(OPEN_TEMPLATES)
        user_text = tmpl.format(app=app_name)
        action = random.choice(["idle", "jump", "spin", "wave", "tapWindow", "pushWidget", "dance", "sit"])
        emotion = random.choice(["happy", "excited", "normal", "curious"])
        reply_tmpl = random.choice(SPEECH_OPEN_REPLIES)
        speech = reply_tmpl.format(app=app_name)
        
        samples.append({
            "messages": [
                {"role": "user", "content": f"CONTEXT: User: {user_text}"},
                {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
            ]
        })

    # 2. Volume & Media Control (~10,000)
    for _ in range(10000):
        if random.random() < 0.6:
            user_text, cmd, speech = random.choice(VOLUME_SCENARIOS)
            action = random.choice(["idle", "tapWindow", "pushWidget", "sit"])
            emotion = "normal"
        else:
            user_text, cmd, speech = random.choice(MEDIA_SCENARIOS)
            action = random.choice(["dance", "headbang", "spin"])
            emotion = random.choice(["happy", "excited", "dj"])

        samples.append({
            "messages": [
                {"role": "user", "content": f"CONTEXT: User: {user_text}"},
                {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
            ]
        })

    # 3. System & Utilities (~5,000)
    for _ in range(5000):
        user_text, cmd, speech = random.choice(SCREEN_SCENARIOS)
        action = random.choice(["backflip", "tapWindow", "climbWindow", "topWindow", "sit"])
        emotion = random.choice(["happy", "curious", "thinking", "normal"])

        samples.append({
            "messages": [
                {"role": "user", "content": f"CONTEXT: User: {user_text}"},
                {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
            ]
        })

    # 4. Tricks & Animations (~10,000)
    for _ in range(10000):
        user_text, action, emotion, speech = random.choice(TRICK_SCENARIOS)
        samples.append({
            "messages": [
                {"role": "user", "content": f"CONTEXT: User: {user_text}"},
                {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: none] {speech}"}
            ]
        })

    # 5. Empathetic Conversations (~10,000)
    for _ in range(10000):
        user_text, action, emotion, cmd, speech = random.choice(EMPATHETIC_CONVERSATIONS)
        samples.append({
            "messages": [
                {"role": "user", "content": f"CONTEXT: User: {user_text}"},
                {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
            ]
        })

    random.shuffle(samples)
    return samples

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    train_path = os.path.join(script_dir, "train.jsonl")

    print("🚀 Generating 50,000 new high-quality 3B training samples...")
    samples = generate_samples(50000)

    print(f"💾 Appending {len(samples)} samples to {train_path}...")
    with open(train_path, "a", encoding="utf-8") as f:
        for item in samples:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    # Re-count total lines
    with open(train_path, "r", encoding="utf-8") as f:
        total = sum(1 for _ in f)

    print(f"🎉 Dataset Expansion Complete! Total lines in train.jsonl: {total}")

if __name__ == "__main__":
    main()
