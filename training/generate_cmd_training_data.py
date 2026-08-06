#!/usr/bin/env python3
"""
Generate ~10,000 diverse CMD training samples for Byte's desktop pet model.

Addresses the severe data imbalance:
  - Before: 86.2% CMD:none (110,164) vs 13.8% CMD:real (17,658)
  - After:  ~80% CMD:none vs ~20% CMD:real  (healthier ratio for 1B model)

All generated commands are constrained to what AIEngine.swift's
isCommandAllowed() security whitelist actually permits:
  1. open -a "App Name"  /  open -a AppName
  2. osascript -e "set volume output volume N"
  3. osascript -e 'tell app "System Events" to set dark mode of appearance preferences to (true|false)'
  4. screencapture ~/Desktop/*.png
  5. pmset sleepnow  /  pmset displaysleepnow

Uses ONLY valid PetAction and PetEmotion enum values from PetBrain.swift.
"""

import json
import random
import os
import itertools

# ============================================================
# Valid enums from PetBrain.swift
# ============================================================
VALID_ACTIONS = [
    "idle", "wander", "followCursor", "sleep", "jump", "sit", "spin", "sulk", "dizzy", "tickled",
    "peekWindow", "sitOnTaskbar", "investigate",
    "stepBack", "dance", "bow", "stretch", "roll", "hide", "chaseLaser", "seekTreat",
    "sitOnCorner", "sitOnMenuBar", "climbWindow", "pushWidget", "tapWindow",
    "sneeze", "backflip", "headbang", "trip", "wave",
]

VALID_EMOTIONS = [
    "happy", "sad", "angry", "curious", "sleepy", "bored", "thinking", "normal", "dizzy",
    "shock", "love", "excited", "embarrassed", "proud",
]

# Actions and emotions commonly used with CMD tasks
CMD_ACTIONS = ["idle", "jump", "spin", "wave", "tapWindow", "pushWidget", "dance",
               "headbang", "sit", "sitOnCorner", "backflip", "stretch", "climbWindow"]
CMD_EMOTIONS_HAPPY = ["happy", "excited", "normal", "proud", "curious"]
CMD_EMOTIONS_DJ = ["happy", "excited"]  # Mapped to happy/excited since "dj" is not in PetEmotion enum
CMD_EMOTIONS_CALM = ["normal", "curious", "happy"]
CMD_EMOTIONS_COZY = ["happy", "love", "normal"]

# ============================================================
# APP DEFINITIONS  (app name, bundle-safe name for `open -a`)
# ============================================================

# Apps already well-represented in training (keep some variety)
EXISTING_APPS = {
    "Spotify": {"cmd": 'open -a Spotify', "emotions": CMD_EMOTIONS_HAPPY,
                "actions": ["tapWindow", "headbang", "dance", "jump", "spin"]},
    "Music": {"cmd": 'open -a Music', "emotions": CMD_EMOTIONS_HAPPY,
              "actions": ["tapWindow", "headbang", "dance", "jump"]},
    "Terminal": {"cmd": 'open -a Terminal', "emotions": CMD_EMOTIONS_CALM,
                 "actions": ["tapWindow", "idle", "sit", "pushWidget"]},
    "Finder": {"cmd": 'open -a Finder', "emotions": CMD_EMOTIONS_CALM,
               "actions": ["tapWindow", "wave", "idle"]},
    "Google Chrome": {"cmd": 'open -a "Google Chrome"', "emotions": CMD_EMOTIONS_CALM,
                      "actions": ["tapWindow", "wave", "idle", "spin"]},
    "Safari": {"cmd": 'open -a Safari', "emotions": CMD_EMOTIONS_CALM,
               "actions": ["tapWindow", "wave", "idle"]},
    "Xcode": {"cmd": 'open -a Xcode', "emotions": CMD_EMOTIONS_CALM,
              "actions": ["tapWindow", "idle", "pushWidget", "sit"]},
    "Calculator": {"cmd": 'open -a Calculator', "emotions": ["normal", "curious"],
                   "actions": ["tapWindow", "idle", "spin"]},
}

# NEW apps missing from training data
NEW_APPS = {
    "Messages": {"cmd": 'open -a Messages', "emotions": ["happy", "excited", "love"],
                 "actions": ["tapWindow", "wave", "jump"]},
    "Calendar": {"cmd": 'open -a Calendar', "emotions": ["normal", "curious", "happy"],
                 "actions": ["tapWindow", "idle", "pushWidget"]},
    "Photos": {"cmd": 'open -a Photos', "emotions": ["happy", "love", "curious"],
               "actions": ["tapWindow", "wave", "climbWindow"]},
    "Maps": {"cmd": 'open -a Maps', "emotions": ["curious", "excited", "happy"],
             "actions": ["tapWindow", "climbWindow", "spin"]},
    "Activity Monitor": {"cmd": 'open -a "Activity Monitor"', "emotions": ["curious", "normal", "thinking"],
                         "actions": ["tapWindow", "idle", "pushWidget"]},
    "FaceTime": {"cmd": 'open -a FaceTime', "emotions": ["happy", "excited", "love"],
                 "actions": ["wave", "jump", "dance"]},
    "App Store": {"cmd": 'open -a "App Store"', "emotions": ["curious", "excited", "happy"],
                  "actions": ["tapWindow", "spin", "jump"]},
    "Visual Studio Code": {"cmd": 'open -a "Visual Studio Code"', "emotions": ["normal", "curious", "proud"],
                           "actions": ["tapWindow", "idle", "pushWidget", "sit"]},
    "Slack": {"cmd": 'open -a Slack', "emotions": ["happy", "normal", "excited"],
              "actions": ["tapWindow", "wave", "jump"]},
    "Discord": {"cmd": 'open -a Discord', "emotions": ["happy", "excited", "love"],
                "actions": ["tapWindow", "wave", "headbang", "dance"]},
    "Telegram": {"cmd": 'open -a Telegram', "emotions": ["happy", "normal", "curious"],
                 "actions": ["tapWindow", "wave", "jump"]},
    "WhatsApp": {"cmd": 'open -a WhatsApp', "emotions": ["happy", "love", "normal"],
                 "actions": ["tapWindow", "wave", "jump"]},
    "Notion": {"cmd": 'open -a Notion', "emotions": ["normal", "curious", "thinking"],
               "actions": ["tapWindow", "idle", "pushWidget"]},
    "Figma": {"cmd": 'open -a Figma', "emotions": ["curious", "excited", "proud"],
              "actions": ["tapWindow", "climbWindow", "idle"]},
    "Arc": {"cmd": 'open -a Arc', "emotions": ["normal", "curious", "happy"],
            "actions": ["tapWindow", "wave", "spin"]},
    "Firefox": {"cmd": 'open -a Firefox', "emotions": ["normal", "curious", "happy"],
                "actions": ["tapWindow", "wave", "idle"]},
    "Brave Browser": {"cmd": 'open -a "Brave Browser"', "emotions": ["normal", "curious", "happy"],
                      "actions": ["tapWindow", "wave", "idle"]},
    "iTerm": {"cmd": 'open -a iTerm', "emotions": ["normal", "curious", "proud"],
              "actions": ["tapWindow", "idle", "pushWidget"]},
    "Warp": {"cmd": 'open -a Warp', "emotions": ["normal", "curious", "excited"],
             "actions": ["tapWindow", "idle", "pushWidget"]},
    "Notes": {"cmd": 'open -a Notes', "emotions": ["normal", "thinking", "curious"],
              "actions": ["tapWindow", "idle", "sit", "pushWidget"]},
    "Reminders": {"cmd": 'open -a Reminders', "emotions": ["normal", "happy", "curious"],
                  "actions": ["tapWindow", "idle", "pushWidget"]},
    "Mail": {"cmd": 'open -a Mail', "emotions": ["normal", "curious", "happy"],
             "actions": ["tapWindow", "idle", "wave"]},
    "Preview": {"cmd": 'open -a Preview', "emotions": ["normal", "curious"],
                "actions": ["tapWindow", "idle", "climbWindow"]},
    "TextEdit": {"cmd": 'open -a TextEdit', "emotions": ["normal", "curious"],
                 "actions": ["tapWindow", "idle", "sit"]},
    "System Settings": {"cmd": "open -a \"System Settings\"", "emotions": ["normal", "curious"],
                        "actions": ["tapWindow", "idle", "pushWidget"]},
    "Podcasts": {"cmd": 'open -a Podcasts', "emotions": ["happy", "curious", "excited"],
                 "actions": ["tapWindow", "sit", "sitOnCorner"]},
    "Books": {"cmd": 'open -a Books', "emotions": ["curious", "happy", "love"],
              "actions": ["tapWindow", "sitOnCorner", "climbWindow"]},
    "Weather": {"cmd": 'open -a Weather', "emotions": ["curious", "normal", "happy"],
                "actions": ["tapWindow", "climbWindow", "idle"]},
    "Clock": {"cmd": 'open -a Clock', "emotions": ["normal", "curious"],
              "actions": ["tapWindow", "idle"]},
}

ALL_APPS = {**EXISTING_APPS, **NEW_APPS}

# ============================================================
# PHRASING TEMPLATES PER CATEGORY
# ============================================================

# --- Open App phrasings ---
OPEN_APP_DIRECT = [
    "open {app}",
    "launch {app}",
    "start {app}",
    "fire up {app}",
    "bring up {app}",
    "open up {app}",
    "can you open {app}",
    "please open {app}",
    "get {app} going",
    "pull up {app}",
    "could you open {app} for me",
    "I need {app}",
    "open {app} for me",
    "run {app}",
    "hey open {app}",
    "yo open {app}",
    "open {app} please",
    "load up {app}",
    "boot up {app}",
    "spin up {app}",
    "pop open {app}",
    "show me {app}",
    "switch to {app}",
    "go to {app}",
    "take me to {app}",
    "let me use {app}",
    "I wanna use {app}",
    "I want {app}",
    "gimme {app}",
    "time for {app}",
]

OPEN_APP_INDIRECT = {
    "Spotify": [
        "play some music", "put on some tunes", "I want to listen to music",
        "let's get some music going", "time for music", "I feel like listening to songs",
        "play my playlist", "hit me with some beats", "I need background music",
        "put on my jams", "I wanna vibe to some music", "music time",
    ],
    "Music": [
        "open my music app", "I want Apple Music", "let's hear some tunes",
        "start the music player", "I want to listen to something", "play my library",
    ],
    "Terminal": [
        "I need the command line", "give me a shell", "I need to run some commands",
        "open a terminal window", "I need the shell", "let me code in terminal",
        "command line please", "I need bash", "give me the terminal",
    ],
    "Google Chrome": [
        "I need to browse", "open my browser", "I want to go online",
        "let me surf the web", "I need to search something", "internet time",
        "open the web browser", "I want to look something up", "I need Google",
    ],
    "Safari": [
        "open my browser", "I need to browse the web", "surf the internet",
        "I want Safari please", "open my default browser",
    ],
    "Visual Studio Code": [
        "I need to code", "let me code", "time to program", "open my editor",
        "open my code editor", "I want to write some code", "coding time",
        "I need my IDE", "let's write some code", "programming time",
        "open my text editor for coding", "launch my dev environment",
    ],
    "Slack": [
        "I need to check messages", "open team chat", "let me check Slack",
        "I need to message my team", "check work messages", "open work chat",
    ],
    "Discord": [
        "I want to chat with friends", "open my gaming chat", "let me check Discord",
        "I wanna talk to my server", "open voice chat", "let's hop on Discord",
    ],
    "Notes": [
        "I need to write something down", "let me take notes", "open my notes",
        "I want to jot something down", "note-taking time", "I need to write a note",
    ],
    "Calendar": [
        "what's on my schedule", "let me check my calendar", "show my appointments",
        "I need to check my schedule", "what meetings do I have", "check my events",
    ],
    "Messages": [
        "I want to text someone", "let me send a message", "open my texts",
        "I need to reply to someone", "check my messages", "let me text",
    ],
    "FaceTime": [
        "I want to video call", "let me make a call", "I need to call someone",
        "video call time", "I want to FaceTime someone",
    ],
    "Maps": [
        "I need directions", "show me the map", "I want to look up a location",
        "where is that place", "I need to find an address", "navigate somewhere",
    ],
    "Photos": [
        "show me my photos", "I want to see my pictures", "open my photo library",
        "let me look at my pictures", "photo gallery please",
    ],
    "Mail": [
        "check my email", "I need to read my emails", "open my inbox",
        "do I have new emails", "let me check my mail", "email time",
    ],
    "Finder": [
        "show my files", "I need to find a file", "open my file manager",
        "let me browse my files", "show me my documents", "I need Finder",
    ],
    "Xcode": [
        "I need to build my app", "open my project", "let me work on my app",
        "time to build", "open my iOS project", "I need to compile",
    ],
    "Activity Monitor": [
        "what's using my CPU", "show system processes", "check what's running",
        "which apps are hogging resources", "I want to see system activity",
    ],
    "App Store": [
        "I want to download an app", "let me check the App Store",
        "are there any app updates", "I need to update my apps",
    ],
    "System Settings": [
        "open settings", "I need to change a setting", "let me adjust my settings",
        "open system preferences", "I need the settings app", "show preferences",
    ],
    "Podcasts": [
        "I want to listen to a podcast", "play my podcasts", "podcast time",
        "let me hear a podcast", "I feel like listening to a podcast",
    ],
    "Books": [
        "I want to read", "open my ebooks", "let me read something",
        "reading time", "I want to read a book",
    ],
    "Weather": [
        "what's the weather like", "check the weather", "is it going to rain",
        "show me the forecast", "how's the weather today",
    ],
    "Notion": [
        "open my workspace", "I need to check my docs", "let me plan something",
        "open my notes workspace", "I need to organize my thoughts",
    ],
    "Figma": [
        "I need to design something", "open my design tool", "let me work on designs",
        "design time", "I want to prototype something",
    ],
    "Arc": [
        "I need a browser", "open my Arc browser", "let me browse with Arc",
        "I want to surf online",
    ],
    "Telegram": [
        "I need to message someone on Telegram", "open my Telegram",
        "check Telegram messages", "let me check Telegram",
    ],
    "WhatsApp": [
        "I need to message on WhatsApp", "open WhatsApp", "check my WhatsApp",
        "I need to reply on WhatsApp",
    ],
    "iTerm": [
        "give me iTerm", "I need iTerm", "open my iTerm terminal",
        "let me use iTerm", "I want the iTerm shell",
    ],
    "Warp": [
        "I need Warp terminal", "open Warp", "give me my Warp shell",
        "let me use Warp",
    ],
    "Firefox": [
        "open Firefox", "I need Firefox browser", "browse with Firefox",
    ],
    "Brave Browser": [
        "open Brave", "I need Brave browser", "browse with Brave",
    ],
    "Reminders": [
        "show my reminders", "what do I need to do", "check my to-do list",
        "I need to set a reminder", "show my tasks",
    ],
    "Calculator": [
        "I need to do some math", "open the calculator", "let me calculate something",
        "I need to crunch some numbers", "math time",
    ],
    "Preview": [
        "I need to view an image", "open Preview", "let me look at a file",
    ],
    "TextEdit": [
        "I need a simple text editor", "open TextEdit", "let me write something quick",
    ],
}

# --- Byte speech responses for opening apps (by category) ---
APP_SPEECH_MUSIC = [
    "Let's set the vibe!", "Here come the beats!", "Music time, let's go!",
    "Queueing up the tunes!", "Your soundtrack awaits!", "Time to jam out!",
    "Opening your music player!", "Let the music flow!", "Beats incoming!",
    "Get ready to groove!", "Your playlist is calling!", "Music is loading up!",
    "Time for some good vibes!", "Let's get the party started!",
    "Your ears deserve this!", "Sound waves incoming!",
]

APP_SPEECH_BROWSER = [
    "Here comes your browser!", "Let's get you online!", "Browser's launching now!",
    "Time to surf!", "Getting you connected!", "Browser loading up!",
    "Internet adventure awaits!", "Let's explore the web!", "Your window to the world!",
    "Opening the web for you!", "Browsing mode activated!", "Let's look it up!",
]

APP_SPEECH_CODE = [
    "Time to build something great!", "Your code editor awaits!", "Let's code!",
    "Coding mode activated!", "Ready to create!", "Your dev tools are spinning up!",
    "Let's write some magic!", "Code canvas is ready!", "Happy coding!",
    "Your workspace is loading!", "Developer mode on!", "Let's ship some code!",
]

APP_SPEECH_COMMUNICATION = [
    "Connecting you now!", "Let's catch up!", "Your messages await!",
    "Time to connect!", "Getting you in touch!", "Chat's opening up!",
    "Communication channels open!", "Let's reach out!",
    "Opening up your chats!", "Stay connected!",
]

APP_SPEECH_PRODUCTIVITY = [
    "Let's get organized!", "Here you go!", "Opening it right up!",
    "Your workspace is ready!", "Time to be productive!", "Let's get to work!",
    "All set for you!", "Ready when you are!", "Your tools are ready!",
    "Bringing it up now!", "Here it comes!", "Loaded and ready!",
]

APP_SPEECH_GENERIC = [
    "Opening it right up!", "Here you go!", "On it!", "Coming right up!",
    "Launching now!", "There you go!", "All yours!", "Opening for you!",
    "Here it comes!", "Got it!", "Right away!", "Opening that up!",
    "Loading it now!", "Spinning it up!", "Say no more!", "At your service!",
]

# Map app names to speech categories
APP_SPEECH_MAP = {
    "Spotify": APP_SPEECH_MUSIC, "Music": APP_SPEECH_MUSIC, "Podcasts": APP_SPEECH_MUSIC,
    "Google Chrome": APP_SPEECH_BROWSER, "Safari": APP_SPEECH_BROWSER,
    "Arc": APP_SPEECH_BROWSER, "Firefox": APP_SPEECH_BROWSER, "Brave Browser": APP_SPEECH_BROWSER,
    "Visual Studio Code": APP_SPEECH_CODE, "Xcode": APP_SPEECH_CODE,
    "Terminal": APP_SPEECH_CODE, "iTerm": APP_SPEECH_CODE, "Warp": APP_SPEECH_CODE,
    "Messages": APP_SPEECH_COMMUNICATION, "Slack": APP_SPEECH_COMMUNICATION,
    "Discord": APP_SPEECH_COMMUNICATION, "Telegram": APP_SPEECH_COMMUNICATION,
    "WhatsApp": APP_SPEECH_COMMUNICATION, "FaceTime": APP_SPEECH_COMMUNICATION, "Mail": APP_SPEECH_COMMUNICATION,
    "Calendar": APP_SPEECH_PRODUCTIVITY, "Notes": APP_SPEECH_PRODUCTIVITY,
    "Reminders": APP_SPEECH_PRODUCTIVITY, "Notion": APP_SPEECH_PRODUCTIVITY,
    "Figma": APP_SPEECH_PRODUCTIVITY,
}

# ============================================================
# VOLUME CONTROL
# ============================================================
VOLUME_LEVELS = list(range(0, 101, 5))  # 0, 5, 10, ..., 100

VOLUME_UP_PHRASES = [
    "turn it up", "louder please", "louder", "bump the volume", "crank it",
    "make it louder", "volume up", "raise the volume", "turn up the volume",
    "I can't hear", "too quiet", "more volume", "increase the volume",
    "a bit louder", "louder please Byte", "max volume", "full volume",
    "blast it", "pump up the volume", "boost the volume", "turn it up loud",
]

VOLUME_DOWN_PHRASES = [
    "turn it down", "quieter please", "quieter", "lower the volume", "shh too loud",
    "make it quieter", "volume down", "reduce the volume", "turn down the volume",
    "too loud", "softer please", "decrease the volume", "a bit quieter",
    "quieter Byte", "ease it down", "bring it down", "lower it",
    "not so loud", "calm the volume", "hush the volume",
]

VOLUME_SET_PHRASES = [
    "set volume to {level}", "volume {level}", "set the volume to {level} percent",
    "make it {level} percent", "volume at {level}", "{level} percent volume",
    "put volume on {level}", "volume to {level} please", "set it to {level}",
    "middle volume please", "half volume", "medium volume",
]

VOLUME_MUTE_PHRASES = [
    "mute", "mute it", "mute the sound", "silence", "shut it up", "no sound",
    "turn off the sound", "kill the audio", "go silent", "mute everything",
    "shush", "quiet mode", "mute the volume", "cut the sound", "hush",
]

VOLUME_UNMUTE_PHRASES = [
    "unmute", "unmute it", "turn sound back on", "bring the sound back",
    "audio back", "sound on", "restore audio", "I want sound again",
    "turn on the sound", "unmute please", "audio back please",
]

VOLUME_UP_SPEECH = [
    "Turning it way up!", "Volume's climbing now!", "Cranking up the sound!",
    "Here comes the volume!", "Louder for you!", "Boosting the sound!",
    "Amping it up!", "Let's make some noise!", "More volume, coming right up!",
]

VOLUME_DOWN_SPEECH = [
    "Easing it down.", "Lowering the volume.", "Quieting things down.",
    "Bringing it down for you.", "Softer now.", "Dialing it back.",
    "Making it gentle.", "Less volume, got it.", "Hushing it down.",
]

VOLUME_SET_SPEECH = [
    "Volume set!", "Done, volume adjusted!", "There you go!", "Set and ready!",
    "All adjusted!", "Volume dialed in!", "Got it, volume changed!",
]

# ============================================================
# DARK/LIGHT MODE
# ============================================================
DARK_MODE_PHRASES = [
    "dark mode", "turn on dark mode", "switch to dark mode", "dark mode on",
    "enable dark mode", "make it dark", "go dark", "I want dark mode",
    "it's dark and the screen's blinding", "my eyes hurt", "too bright",
    "night mode", "dark theme please", "dark mode please", "dim it",
    "switch to dark theme", "activate dark mode", "dark everything",
    "the screen is too bright", "I need dark mode", "easier on the eyes",
    "dark side please", "time for dark mode", "dark interface please",
]

LIGHT_MODE_PHRASES = [
    "light mode", "turn on light mode", "switch to light mode", "light mode on",
    "enable light mode", "make it bright", "go light", "I want light mode",
    "bright mode", "light theme please", "light mode please", "brighten it",
    "switch to light theme", "activate light mode", "day mode",
    "I can't see in dark mode", "turn off dark mode", "disable dark mode",
    "light interface please",
]

DARK_MODE_SPEECH = [
    "Going dark!", "Dark mode activated!", "Dimming things for you!",
    "Night vibes on!", "Easy on the eyes now!", "Dark mode is your friend.",
    "Switching to the dark side!", "Cozy darkness enabled!", "Dark theme on!",
]

LIGHT_MODE_SPEECH = [
    "Let there be light!", "Brightening things up!", "Light mode on!",
    "Sunshine mode activated!", "Back to the bright side!", "Light theme enabled!",
    "Bright and clear now!", "Everything is brighter now!", "Day mode on!",
]

# ============================================================
# SCREENSHOT
# ============================================================
SCREENSHOT_PHRASES = [
    "take a screenshot", "screenshot", "snap the screen", "capture the screen",
    "screen capture", "take a screen grab", "screenshot please", "screencap",
    "grab the screen", "snap it", "capture this", "screenshot this",
    "save the screen", "take a pic of the screen", "screen snap",
    "I need a screenshot", "can you screenshot", "get a screenshot",
    "capture my screen", "screen shot",
]

SCREENSHOT_SPEECH = [
    "Screenshot captured!", "Saved to your Desktop!", "Got it! Captured and saved!",
    "Click! Screenshot taken!", "Screen captured for you!", "Snap! There it is!",
    "Picture taken!", "Your screen is saved!", "Captured! Check your Desktop!",
]

# ============================================================
# SLEEP
# ============================================================
SLEEP_PHRASES = [
    "put the Mac to sleep", "sleep mode", "sleep", "put it to sleep",
    "goodnight Mac", "time to sleep", "nap time for the Mac",
    "send the Mac to sleep", "sleep the computer", "Mac sleep now",
    "power nap", "hibernate", "shut the screen", "sleep mode please",
    "let the Mac rest", "sleepy time", "go to sleep Mac",
    "night night Mac", "let the computer rest", "shut it down for a bit",
]

SLEEP_SPEECH = [
    "Sweet dreams, Mac!", "Putting it to sleep now.", "Night night!",
    "Sleep mode activated!", "Time for a nap.", "Goodnight!",
    "Rest easy.", "Your Mac is going to sleep.", "Zzz... sleep mode on.",
]


def make_sample(user_text, action, emotion, cmd, speech):
    """Create a training sample in the project's JSONL format."""
    return {
        "messages": [
            {"role": "user", "content": f"CONTEXT: User: {user_text}"},
            {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
        ]
    }


def make_sample_env(context, action, emotion, cmd, speech):
    """Create a training sample with a non-user context (environment-triggered)."""
    return {
        "messages": [
            {"role": "user", "content": f"CONTEXT: {context}"},
            {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
        ]
    }


def generate_all_samples():
    samples = []
    rng = random.Random(42)

    # ================================================================
    # 1. OPEN APP — DIRECT PHRASINGS  (~3,600 samples)
    # ================================================================
    for app_name, info in ALL_APPS.items():
        cmd = info["cmd"]
        app_actions = info["actions"]
        app_emotions = info["emotions"]
        speech_pool = APP_SPEECH_MAP.get(app_name, APP_SPEECH_GENERIC)

        # Pick N direct phrasings per app
        # New apps get more (20), existing well-covered apps get fewer (8)
        n_direct = 20 if app_name in NEW_APPS else 8
        chosen_phrases = rng.sample(OPEN_APP_DIRECT, min(n_direct, len(OPEN_APP_DIRECT)))

        for phrase in chosen_phrases:
            user_text = phrase.format(app=app_name)
            action = rng.choice(app_actions)
            emotion = rng.choice(app_emotions)
            speech = rng.choice(speech_pool)
            samples.append(make_sample(user_text, action, emotion, cmd, speech))

    # ================================================================
    # 2. OPEN APP — INDIRECT/CONVERSATIONAL PHRASINGS  (~2,000 samples)
    # ================================================================
    for app_name, phrases in OPEN_APP_INDIRECT.items():
        info = ALL_APPS[app_name]
        cmd = info["cmd"]
        app_actions = info["actions"]
        app_emotions = info["emotions"]
        speech_pool = APP_SPEECH_MAP.get(app_name, APP_SPEECH_GENERIC)

        # Generate multiple variations per indirect phrase
        for phrase in phrases:
            n_variations = rng.randint(3, 6)
            for _ in range(n_variations):
                action = rng.choice(app_actions)
                emotion = rng.choice(app_emotions)
                speech = rng.choice(speech_pool)
                samples.append(make_sample(phrase, action, emotion, cmd, speech))

    # ================================================================
    # 3. VOLUME CONTROL  (~2,000 samples)
    # ================================================================

    # Volume UP: map to high volumes (60-100)
    for phrase in VOLUME_UP_PHRASES:
        for _ in range(rng.randint(4, 8)):
            level = rng.choice([60, 65, 70, 75, 80, 85, 90, 95, 100])
            cmd = f'osascript -e "set volume output volume {level}"'
            action = rng.choice(["jump", "headbang", "dance", "pushWidget", "spin"])
            emotion = rng.choice(["happy", "excited"])
            speech = rng.choice(VOLUME_UP_SPEECH)
            samples.append(make_sample(phrase, action, emotion, cmd, speech))

    # Volume DOWN: map to low volumes (5-40)
    for phrase in VOLUME_DOWN_PHRASES:
        for _ in range(rng.randint(4, 8)):
            level = rng.choice([5, 10, 15, 20, 25, 30, 35, 40])
            cmd = f'osascript -e "set volume output volume {level}"'
            action = rng.choice(["pushWidget", "sit", "sitOnCorner", "idle"])
            emotion = rng.choice(["normal", "happy", "curious"])
            speech = rng.choice(VOLUME_DOWN_SPEECH)
            samples.append(make_sample(phrase, action, emotion, cmd, speech))

    # Volume SET: explicit level
    for phrase_template in VOLUME_SET_PHRASES:
        for level in rng.sample(VOLUME_LEVELS, min(8, len(VOLUME_LEVELS))):
            phrase = phrase_template.format(level=level)
            cmd = f'osascript -e "set volume output volume {level}"'
            action = rng.choice(["pushWidget", "idle", "spin", "tapWindow"])
            emotion = rng.choice(["normal", "happy"])
            speech = rng.choice(VOLUME_SET_SPEECH)
            samples.append(make_sample(phrase, action, emotion, cmd, speech))

    # NOTE: Mute/unmute commands are NOT in the security whitelist
    # (osascript -e "set volume with output muted true/false" is not matched)
    # So we skip mute/unmute to avoid training the model on blocked commands.
    # If you add mute/unmute to the whitelist, uncomment below:

    # # Volume MUTE
    # for phrase in VOLUME_MUTE_PHRASES:
    #     for _ in range(rng.randint(2, 4)):
    #         cmd = 'osascript -e "set volume with output muted true"'
    #         ...

    # Instead, train mute → volume 0, unmute → volume 50
    for phrase in VOLUME_MUTE_PHRASES:
        for _ in range(rng.randint(2, 4)):
            cmd = 'osascript -e "set volume output volume 0"'
            action = rng.choice(["pushWidget", "sit", "idle", "sitOnCorner"])
            emotion = rng.choice(["normal", "happy"])
            speech = rng.choice(["Muting by setting volume to zero.", "Going silent.", "Volume zeroed out.",
                                 "All quiet now.", "Sound off!", "Silence is golden.", "Hushed."])
            samples.append(make_sample(phrase, action, emotion, cmd, speech))

    for phrase in VOLUME_UNMUTE_PHRASES:
        for _ in range(rng.randint(2, 4)):
            cmd = 'osascript -e "set volume output volume 50"'
            action = rng.choice(["wave", "spin", "jump", "pushWidget"])
            emotion = rng.choice(["happy", "normal", "excited"])
            speech = rng.choice(["Sound is back!", "Restored to fifty percent.", "Audio's on!",
                                 "Welcome back, sound!", "Volume restored!"])
            samples.append(make_sample(phrase, action, emotion, cmd, speech))

    # ================================================================
    # 4. DARK / LIGHT MODE  (~600 samples)
    # ================================================================
    dark_cmd = "osascript -e 'tell app \"System Events\" to set dark mode of appearance preferences to true'"
    light_cmd = "osascript -e 'tell app \"System Events\" to set dark mode of appearance preferences to false'"

    for phrase in DARK_MODE_PHRASES:
        for _ in range(rng.randint(3, 6)):
            action = rng.choice(["pushWidget", "sitOnCorner", "idle", "tapWindow"])
            emotion = rng.choice(["happy", "normal", "curious"])
            speech = rng.choice(DARK_MODE_SPEECH)
            samples.append(make_sample(phrase, action, emotion, cmd=dark_cmd, speech=speech))

    for phrase in LIGHT_MODE_PHRASES:
        for _ in range(rng.randint(3, 6)):
            action = rng.choice(["wave", "spin", "idle", "jump"])
            emotion = rng.choice(["happy", "normal", "excited"])
            speech = rng.choice(LIGHT_MODE_SPEECH)
            samples.append(make_sample(phrase, action, emotion, cmd=light_cmd, speech=speech))

    # ================================================================
    # 5. SCREENSHOT  (~400 samples)
    # ================================================================
    screenshot_cmd = "screencapture ~/Desktop/screenshot.png"

    for phrase in SCREENSHOT_PHRASES:
        for _ in range(rng.randint(3, 5)):
            action = rng.choice(["wave", "jump", "tapWindow", "spin"])
            emotion = rng.choice(["happy", "excited", "normal"])
            speech = rng.choice(SCREENSHOT_SPEECH)
            samples.append(make_sample(phrase, action, emotion, cmd=screenshot_cmd, speech=speech))

    # ================================================================
    # 6. SLEEP MAC  (~300 samples)
    # ================================================================
    for phrase in SLEEP_PHRASES:
        for _ in range(rng.randint(3, 5)):
            action = rng.choice(["sleep", "idle", "sitOnCorner", "sit", "wave"])
            emotion = rng.choice(["sleepy", "normal", "happy"])
            speech = rng.choice(SLEEP_SPEECH)
            samples.append(make_sample(phrase, action, emotion, cmd="pmset sleepnow", speech=speech))

    # ================================================================
    # 7. CONTEXTUAL / SITUATIONAL CMD TRIGGERS  (~800 samples)
    # ================================================================
    # Teach the model to issue commands based on environmental context,
    # not just direct user requests.

    contextual_scenarios = [
        # Late night → suggest dark mode
        ("USER SAID: 'It's so late, the screen is killing my eyes'. EMOTION: sleepy.",
         "sitOnCorner", "sleepy", dark_cmd, "Let me dim things down for those tired eyes."),
        ("It's 11 PM and user has been working. EMOTION: sleepy.",
         "sitOnCorner", "sleepy", dark_cmd, "Late night calls for dark mode. Easier on your eyes!"),
        ("USER SAID: 'It's really bright in here'. EMOTION: normal.",
         "idle", "normal", light_cmd, "Switching to light mode to match the room!"),

        # User mentions wanting to do something → open relevant app
        ("USER SAID: 'I have an email to write'. EMOTION: normal.",
         "tapWindow", "normal", 'open -a Mail', "Let me get your inbox ready!"),
        ("USER SAID: 'I need to check my schedule for tomorrow'. EMOTION: curious.",
         "tapWindow", "curious", 'open -a Calendar', "Let's see what tomorrow looks like!"),
        ("USER SAID: 'I should check if I have any new messages'. EMOTION: curious.",
         "tapWindow", "curious", 'open -a Messages', "Let's see what's waiting for you!"),
        ("USER SAID: 'I feel like watching some photos from the trip'. EMOTION: love.",
         "tapWindow", "love", 'open -a Photos', "Let's revisit those memories!"),
        ("USER SAID: 'I want to start designing the UI'. EMOTION: curious.",
         "tapWindow", "curious", 'open -a Figma', "Design mode activated!"),
        ("USER SAID: 'Time to write some Swift code'. EMOTION: normal.",
         "tapWindow", "normal", 'open -a Xcode', "Let's build something awesome!"),
        ("USER SAID: 'I need to look up a recipe'. EMOTION: curious.",
         "tapWindow", "curious", 'open -a Safari', "Let's find something delicious!"),
        ("USER SAID: 'I should call mom'. EMOTION: love.",
         "wave", "love", 'open -a FaceTime', "Let's connect with mom!"),
        ("USER SAID: 'I need to organize my project notes'. EMOTION: thinking.",
         "tapWindow", "thinking", 'open -a Notes', "Let's get those notes organized!"),
        ("USER SAID: 'time to catch up on the podcast'. EMOTION: happy.",
         "sitOnCorner", "happy", 'open -a Podcasts', "Podcast time! Let's listen!"),
        ("USER SAID: 'I want to read my book'. EMOTION: curious.",
         "sitOnCorner", "curious", 'open -a Books', "Reading time! Enjoy!"),
        ("USER SAID: 'how's the weather gonna be'. EMOTION: curious.",
         "climbWindow", "curious", 'open -a Weather', "Let me check the forecast for you!"),
        ("USER SAID: 'I got work to do in the shell'. EMOTION: normal.",
         "tapWindow", "normal", 'open -a Terminal', "Shell's ready when you are!"),
        ("USER SAID: 'I want to check what's happening on the server'. EMOTION: curious.",
         "tapWindow", "curious", 'open -a Terminal', "Let's take a look!"),
        ("USER SAID: 'let me plan my week'. EMOTION: thinking.",
         "tapWindow", "thinking", 'open -a Calendar', "Let's organize the week ahead!"),
        ("USER SAID: 'I need to sketch out a wireframe'. EMOTION: curious.",
         "tapWindow", "curious", 'open -a Figma', "Wireframing mode on!"),
        ("USER SAID: 'gotta check Slack before the standup'. EMOTION: normal.",
         "tapWindow", "normal", 'open -a Slack', "Let's catch up on messages first!"),
        ("USER SAID: 'the guys are all on Discord'. EMOTION: excited.",
         "wave", "excited", 'open -a Discord', "Let's join the crew!"),
    ]

    # Generate variations of each contextual scenario
    for ctx, action, emotion, cmd, speech in contextual_scenarios:
        # Add the base version
        samples.append(make_sample_env(ctx, action, emotion, cmd, speech))
        # Add 10-15 variations with shuffled actions/emotions
        for _ in range(rng.randint(10, 15)):
            alt_action = rng.choice(ALL_APPS.get(
                next((k for k, v in ALL_APPS.items() if v["cmd"] == cmd), ""),
                {"actions": CMD_ACTIONS}
            ).get("actions", CMD_ACTIONS))
            # Keep emotion pool relevant
            alt_emotion = rng.choice(CMD_EMOTIONS_HAPPY if emotion in ["happy", "excited"] else CMD_EMOTIONS_CALM)
            samples.append(make_sample_env(ctx, alt_action, alt_emotion, cmd, speech))

    # ================================================================
    # 8. COMPOUND / POLITE PHRASINGS  (~500 samples)
    # ================================================================
    polite_prefixes = [
        "hey Byte, ", "Byte, ", "yo Byte ", "hey buddy, ", "please ",
        "could you ", "can you ", "would you mind ", "Byte could you ",
        "Byte please ", "hey can you ", "",
    ]

    # Re-use some direct phrasings with polite prefixes for variety
    compound_apps = rng.sample(list(ALL_APPS.keys()), min(15, len(ALL_APPS)))
    for app_name in compound_apps:
        info = ALL_APPS[app_name]
        cmd = info["cmd"]
        app_actions = info["actions"]
        app_emotions = info["emotions"]
        speech_pool = APP_SPEECH_MAP.get(app_name, APP_SPEECH_GENERIC)

        base_phrases = [f"open {app_name}", f"launch {app_name}", f"start {app_name}"]
        for base in base_phrases:
            for prefix in rng.sample(polite_prefixes, min(4, len(polite_prefixes))):
                user_text = prefix + base
                action = rng.choice(app_actions)
                emotion = rng.choice(app_emotions)
                speech = rng.choice(speech_pool)
                samples.append(make_sample(user_text.strip(), action, emotion, cmd, speech))

    # ================================================================
    # SHUFFLE AND RETURN
    # ================================================================
    rng.shuffle(samples)
    return samples


def main():
    output_dir = os.path.dirname(os.path.abspath(__file__))
    train_path = os.path.join(output_dir, "train.jsonl")
    test_path = os.path.join(output_dir, "test.jsonl")
    valid_path = os.path.join(output_dir, "valid.jsonl")

    print("Generating CMD training samples...")
    all_samples = generate_all_samples()
    total = len(all_samples)
    print(f"Generated {total} CMD samples total.")

    # Split: 95% train, 2.5% test, 2.5% valid
    rng = random.Random(123)
    rng.shuffle(all_samples)

    test_count = max(1, int(total * 0.025))
    valid_count = max(1, int(total * 0.025))
    train_count = total - test_count - valid_count

    train_samples = all_samples[:train_count]
    test_samples = all_samples[train_count:train_count + test_count]
    valid_samples = all_samples[train_count + test_count:]

    print(f"  Train: {len(train_samples)}")
    print(f"  Test:  {len(test_samples)}")
    print(f"  Valid: {len(valid_samples)}")

    # Append to existing files
    for path, samples, label in [
        (train_path, train_samples, "train"),
        (test_path, test_samples, "test"),
        (valid_path, valid_samples, "valid"),
    ]:
        with open(path, "a", encoding="utf-8") as f:
            for sample in samples:
                f.write(json.dumps(sample, ensure_ascii=False) + "\n")
        print(f"  Appended {len(samples)} samples to {label}.jsonl")

    # Summary stats
    print(f"\n--- Summary ---")
    # Count total lines in train.jsonl
    with open(train_path) as f:
        total_train = sum(1 for _ in f)
    # Count CMD: none vs real
    cmd_none = 0
    cmd_real = 0
    with open(train_path) as f:
        for line in f:
            data = json.loads(line)
            if "messages" in data:
                text = data["messages"][-1]["content"]
            elif "text" in data:
                text = data["text"]
            else:
                continue
            if "[CMD: none]" in text:
                cmd_none += 1
            elif "[CMD:" in text:
                cmd_real += 1
    print(f"Total train.jsonl lines: {total_train}")
    print(f"  CMD: none  = {cmd_none} ({100*cmd_none/total_train:.1f}%)")
    print(f"  CMD: real  = {cmd_real} ({100*cmd_real/total_train:.1f}%)")
    print(f"  No CMD tag = {total_train - cmd_none - cmd_real}")


if __name__ == "__main__":
    main()
