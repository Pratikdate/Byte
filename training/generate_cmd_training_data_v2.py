#!/usr/bin/env python3
"""
Generate additional CMD training samples through heavy combinatorial expansion
to reach a 20% CMD ratio in the training data.

This is a supplementary generator — run AFTER generate_cmd_training_data.py.
Target: ~7,500 additional samples.
"""

import json
import random
import os

# Valid enums
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

# Commonly-used subsets for CMD tasks
ACTIVE_ACTIONS = ["idle", "jump", "spin", "wave", "tapWindow", "pushWidget", "dance",
                  "headbang", "sit", "sitOnCorner", "backflip", "stretch", "climbWindow",
                  "roll", "bow", "peekWindow", "investigate"]
HAPPY_EMOTIONS = ["happy", "excited", "normal", "proud", "curious", "love"]
CALM_EMOTIONS = ["normal", "curious", "happy", "thinking"]


def make_sample(user_text, action, emotion, cmd, speech):
    return {
        "messages": [
            {"role": "user", "content": f"CONTEXT: User: {user_text}"},
            {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
        ]
    }


def make_ctx_sample(ctx, action, emotion, cmd, speech):
    return {
        "messages": [
            {"role": "user", "content": f"CONTEXT: {ctx}"},
            {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
        ]
    }


# ============================================================
# MEGA PHRASING LISTS — Much more variety
# ============================================================

# User ways to ask for an app
OPEN_TEMPLATES = [
    "open {a}", "launch {a}", "start {a}", "fire up {a}", "bring up {a}", "open up {a}",
    "can you open {a}", "please open {a}", "get {a} going", "pull up {a}",
    "could you open {a} for me", "I need {a}", "open {a} for me", "run {a}",
    "hey open {a}", "open {a} please", "load up {a}", "boot up {a}", "spin up {a}",
    "pop open {a}", "show me {a}", "switch to {a}", "go to {a}", "take me to {a}",
    "let me use {a}", "I wanna use {a}", "I want {a}", "gimme {a}", "time for {a}",
    "let's use {a}", "I'd like {a}", "get me {a}", "hit {a}", "throw on {a}",
    "activate {a}", "start up {a}", "kick off {a}", "set up {a}", "turn on {a}",
    "I wanna open {a}", "can you start {a}", "please launch {a}", "fire it up, {a}",
    "bring me {a}", "load {a}", "wake up {a}", "init {a}", "launch {a} for me",
    "real quick open {a}", "quickly launch {a}", "hurry and open {a}",
    "I need {a} right now", "get {a} started", "let's fire up {a}",
]

# Polite / personality prefixes
PREFIXES = [
    "", "", "", "",  # empty prefix is most common (weighted)
    "hey Byte, ", "Byte, ", "yo Byte ", "hey buddy, ", "please ",
    "could you ", "can you ", "Byte could you ", "Byte please ", "hey can you ",
    "do me a favor and ", "be a pal and ", "quickly ",
]

# Speech pools
SPEECH_MUSIC = [
    "Let's set the vibe!", "Here come the beats!", "Music time, let's go!",
    "Queueing up the tunes!", "Your soundtrack awaits!", "Time to jam out!",
    "Opening your music player!", "Let the music flow!", "Beats incoming!",
    "Get ready to groove!", "Your playlist is calling!", "Music is loading up!",
    "Time for some good vibes!", "Let's get the party started!", "Tune time!",
    "Sound waves incoming!", "DJ Byte, at your service!", "The vibes are loading!",
]

SPEECH_BROWSER = [
    "Here comes your browser!", "Let's get you online!", "Browser's launching now!",
    "Time to surf!", "Getting you connected!", "Browser loading up!",
    "Internet adventure awaits!", "Let's explore the web!", "Your window to the world!",
    "Opening the web for you!", "Browsing mode activated!", "Let's look it up!",
    "The web awaits!", "Online in a flash!", "Loading the internet!",
]

SPEECH_CODE = [
    "Time to build something great!", "Your code editor awaits!", "Let's code!",
    "Coding mode activated!", "Ready to create!", "Your dev tools are spinning up!",
    "Let's write some magic!", "Code canvas is ready!", "Happy coding!",
    "Your workspace is loading!", "Developer mode on!", "Let's ship some code!",
    "Let's build!", "Editor's ready for you!", "Time to create!",
]

SPEECH_CHAT = [
    "Connecting you now!", "Let's catch up!", "Your messages await!",
    "Time to connect!", "Getting you in touch!", "Chat's opening up!",
    "Communication channels open!", "Let's reach out!", "Opening up your chats!",
    "Stay connected!", "Chat mode on!", "Your friends await!",
]

SPEECH_PROD = [
    "Let's get organized!", "Here you go!", "Opening it right up!",
    "Your workspace is ready!", "Time to be productive!", "Let's get to work!",
    "All set for you!", "Ready when you are!", "Your tools are ready!",
    "Bringing it up now!", "Here it comes!", "Loaded and ready!",
    "Productivity boost incoming!", "Time to focus!", "Let's do this!",
]

SPEECH_GENERIC = [
    "Opening it right up!", "Here you go!", "On it!", "Coming right up!",
    "Launching now!", "There you go!", "All yours!", "Opening for you!",
    "Here it comes!", "Got it!", "Right away!", "Opening that up!",
    "Loading it now!", "Spinning it up!", "Say no more!", "At your service!",
    "You got it!", "No problem!", "Done!", "Here we go!", "Boom, launched!",
]

# All apps with their details
APPS = {
    # Music apps
    "Spotify":      ("open -a Spotify",               SPEECH_MUSIC, ["tapWindow","headbang","dance","jump","spin"], HAPPY_EMOTIONS),
    "Music":        ("open -a Music",                  SPEECH_MUSIC, ["tapWindow","headbang","dance","jump"],        HAPPY_EMOTIONS),
    "Podcasts":     ("open -a Podcasts",               SPEECH_MUSIC, ["tapWindow","sit","sitOnCorner"],             HAPPY_EMOTIONS),
    # Browsers
    "Google Chrome":("open -a \"Google Chrome\"",      SPEECH_BROWSER, ["tapWindow","wave","idle","spin"],          CALM_EMOTIONS),
    "Safari":       ("open -a Safari",                 SPEECH_BROWSER, ["tapWindow","wave","idle"],                 CALM_EMOTIONS),
    "Arc":          ("open -a Arc",                    SPEECH_BROWSER, ["tapWindow","wave","spin"],                 CALM_EMOTIONS),
    "Firefox":      ("open -a Firefox",                SPEECH_BROWSER, ["tapWindow","wave","idle"],                 CALM_EMOTIONS),
    "Brave Browser":("open -a \"Brave Browser\"",      SPEECH_BROWSER, ["tapWindow","wave","idle"],                 CALM_EMOTIONS),
    # Code/Dev
    "Visual Studio Code": ("open -a \"Visual Studio Code\"", SPEECH_CODE, ["tapWindow","idle","pushWidget","sit"], CALM_EMOTIONS),
    "Xcode":        ("open -a Xcode",                  SPEECH_CODE, ["tapWindow","idle","pushWidget","sit"],        CALM_EMOTIONS),
    "Terminal":     ("open -a Terminal",                SPEECH_CODE, ["tapWindow","idle","sit","pushWidget"],        CALM_EMOTIONS),
    "iTerm":        ("open -a iTerm",                  SPEECH_CODE, ["tapWindow","idle","pushWidget"],              CALM_EMOTIONS),
    "Warp":         ("open -a Warp",                   SPEECH_CODE, ["tapWindow","idle","pushWidget"],              CALM_EMOTIONS),
    # Communication
    "Messages":     ("open -a Messages",               SPEECH_CHAT, ["tapWindow","wave","jump"],                    HAPPY_EMOTIONS),
    "Slack":        ("open -a Slack",                  SPEECH_CHAT, ["tapWindow","wave","jump"],                    HAPPY_EMOTIONS),
    "Discord":      ("open -a Discord",                SPEECH_CHAT, ["tapWindow","wave","headbang","dance"],        HAPPY_EMOTIONS),
    "Telegram":     ("open -a Telegram",               SPEECH_CHAT, ["tapWindow","wave","jump"],                   HAPPY_EMOTIONS),
    "WhatsApp":     ("open -a WhatsApp",               SPEECH_CHAT, ["tapWindow","wave","jump"],                   HAPPY_EMOTIONS),
    "FaceTime":     ("open -a FaceTime",               SPEECH_CHAT, ["wave","jump","dance"],                       HAPPY_EMOTIONS),
    "Mail":         ("open -a Mail",                   SPEECH_CHAT, ["tapWindow","idle","wave"],                   CALM_EMOTIONS),
    # Productivity
    "Calendar":     ("open -a Calendar",               SPEECH_PROD, ["tapWindow","idle","pushWidget"],             CALM_EMOTIONS),
    "Notes":        ("open -a Notes",                  SPEECH_PROD, ["tapWindow","idle","sit","pushWidget"],        CALM_EMOTIONS),
    "Reminders":    ("open -a Reminders",              SPEECH_PROD, ["tapWindow","idle","pushWidget"],             CALM_EMOTIONS),
    "Notion":       ("open -a Notion",                 SPEECH_PROD, ["tapWindow","idle","pushWidget"],             CALM_EMOTIONS),
    "Figma":        ("open -a Figma",                  SPEECH_PROD, ["tapWindow","climbWindow","idle"],            CALM_EMOTIONS),
    # Utilities
    "Finder":       ("open -a Finder",                 SPEECH_GENERIC, ["tapWindow","wave","idle"],                CALM_EMOTIONS),
    "Calculator":   ("open -a Calculator",             SPEECH_GENERIC, ["tapWindow","idle","spin"],                CALM_EMOTIONS),
    "Photos":       ("open -a Photos",                 SPEECH_GENERIC, ["tapWindow","wave","climbWindow"],         HAPPY_EMOTIONS),
    "Maps":         ("open -a Maps",                   SPEECH_GENERIC, ["tapWindow","climbWindow","spin"],         ["curious","excited","happy"]),
    "Activity Monitor": ("open -a \"Activity Monitor\"", SPEECH_GENERIC, ["tapWindow","idle","pushWidget"],        CALM_EMOTIONS),
    "App Store":    ("open -a \"App Store\"",           SPEECH_GENERIC, ["tapWindow","spin","jump"],               HAPPY_EMOTIONS),
    "System Settings": ("open -a \"System Settings\"",  SPEECH_GENERIC, ["tapWindow","idle","pushWidget"],         CALM_EMOTIONS),
    "Books":        ("open -a Books",                  SPEECH_GENERIC, ["tapWindow","sitOnCorner","climbWindow"],   HAPPY_EMOTIONS),
    "Weather":      ("open -a Weather",                SPEECH_GENERIC, ["tapWindow","climbWindow","idle"],         ["curious","normal","happy"]),
    "Preview":      ("open -a Preview",                SPEECH_GENERIC, ["tapWindow","idle","climbWindow"],         CALM_EMOTIONS),
    "TextEdit":     ("open -a TextEdit",               SPEECH_GENERIC, ["tapWindow","idle","sit"],                 CALM_EMOTIONS),
    "Clock":        ("open -a Clock",                  SPEECH_GENERIC, ["tapWindow","idle"],                       CALM_EMOTIONS),
}

# Alternate names users might use for apps
APP_ALIASES = {
    "Spotify": ["Spotify", "spotify"],
    "Music": ["Music", "Apple Music", "the music app", "my music"],
    "Google Chrome": ["Chrome", "Google Chrome", "the browser", "my browser"],
    "Safari": ["Safari", "the Safari browser"],
    "Visual Studio Code": ["VS Code", "VSCode", "Visual Studio Code", "Code", "my editor", "my code editor"],
    "Terminal": ["Terminal", "the terminal", "the shell", "terminal", "a terminal"],
    "Xcode": ["Xcode", "my Xcode project"],
    "Finder": ["Finder", "the file manager", "my files"],
    "Messages": ["Messages", "iMessage", "my texts", "the texting app"],
    "Calendar": ["Calendar", "my calendar", "the calendar app"],
    "Notes": ["Notes", "my notes", "the notes app"],
    "Mail": ["Mail", "my email", "the mail app", "my inbox"],
    "Discord": ["Discord", "disc"],
    "Slack": ["Slack", "my Slack", "work chat"],
    "Notion": ["Notion", "my Notion"],
    "Figma": ["Figma", "my Figma"],
    "Activity Monitor": ["Activity Monitor", "the activity monitor", "task manager"],
    "System Settings": ["Settings", "System Settings", "System Preferences", "preferences", "system preferences"],
    "FaceTime": ["FaceTime", "video call"],
    "Photos": ["Photos", "my photos", "the photo library", "my pictures"],
    "Maps": ["Maps", "the map app", "Apple Maps"],
    "Calculator": ["Calculator", "the calculator", "calc"],
    "Arc": ["Arc", "the Arc browser"],
    "iTerm": ["iTerm", "iTerm2"],
    "Warp": ["Warp", "Warp terminal"],
    "Podcasts": ["Podcasts", "the Podcasts app", "my podcasts"],
    "Books": ["Books", "Apple Books", "my books"],
    "Weather": ["Weather", "the weather app"],
}


def generate_app_samples(rng):
    """Generate open-app samples with massive combinatorial expansion."""
    samples = []
    
    for app_name, (cmd, speech_pool, actions, emotions) in APPS.items():
        aliases = APP_ALIASES.get(app_name, [app_name])
        
        for alias in aliases:
            # Pick a subset of templates for this alias
            n_templates = min(20, len(OPEN_TEMPLATES))
            chosen_templates = rng.sample(OPEN_TEMPLATES, n_templates)
            
            for template in chosen_templates:
                # For each template, pick 1-2 prefix variations
                n_prefix = rng.randint(1, 2)
                for prefix in rng.sample(PREFIXES, n_prefix):
                    user_text = (prefix + template.format(a=alias)).strip()
                    action = rng.choice(actions)
                    emotion = rng.choice(emotions)
                    speech = rng.choice(speech_pool)
                    samples.append(make_sample(user_text, action, emotion, cmd, speech))
    
    return samples


def generate_volume_samples(rng):
    """Generate expanded volume control samples."""
    samples = []
    
    # Conversational volume requests
    volume_conversations = [
        # Increasing
        ("it's too quiet in here", [60,65,70,75,80], "happy", "Pumping up the volume!"),
        ("I can barely hear it", [65,70,75,80,85], "normal", "Let me turn that up for you!"),
        ("louder!", [70,75,80,85,90], "excited", "Here it comes, louder!"),
        ("make it boom", [85,90,95,100], "excited", "Boom! Volume cranked!"),
        ("I want it blasting", [90,95,100], "excited", "Full blast mode!"),
        ("a tiny bit louder", [55,60,65], "normal", "Just a touch louder."),
        ("bump it up a notch", [60,65,70], "happy", "Notched it up!"),
        ("that's not enough volume", [70,75,80], "normal", "How about now?"),
        ("MORE volume", [80,85,90], "excited", "MORE it is!"),
        ("I want the whole block to hear", [95,100], "excited", "The neighbors will love this!"),
        # Decreasing
        ("it's too loud", [20,25,30,35], "normal", "Bringing it down."),
        ("way too much volume", [15,20,25], "normal", "Dialing it way back."),
        ("my ears are hurting", [10,15,20], "normal", "Let me save your ears."),
        ("a little softer", [35,40,45], "normal", "Just a bit softer."),
        ("keep it low", [15,20,25], "normal", "Nice and low."),
        ("background level", [20,25,30], "normal", "Set to background level."),
        ("whisper volume", [5,10], "happy", "Whisper quiet now."),
        ("just a murmur", [10,15], "normal", "Nice and gentle."),
        ("tone it down", [30,35,40], "normal", "Toned it down!"),
        ("not so loud please", [25,30,35], "normal", "Quieter for you."),
        # Specific
        ("fifty percent", [50], "normal", "Right in the middle!"),
        ("halfway", [50], "normal", "Set to fifty percent!"),
        ("a quarter volume", [25], "normal", "Twenty-five percent, done!"),
        ("three quarters", [75], "happy", "Seventy-five percent, nice!"),
        ("one hundred percent", [100], "excited", "Max volume!"),
        ("zero volume", [0], "normal", "Total silence."),
    ]
    
    vol_up_actions = ["jump", "headbang", "dance", "pushWidget", "spin", "backflip"]
    vol_down_actions = ["pushWidget", "sit", "sitOnCorner", "idle", "tapWindow"]
    vol_set_actions = ["pushWidget", "idle", "spin", "tapWindow", "sit"]
    
    for phrase, levels, base_emotion, base_speech in volume_conversations:
        for _ in range(rng.randint(5, 10)):
            level = rng.choice(levels)
            cmd = f'osascript -e "set volume output volume {level}"'
            
            if level >= 60:
                action = rng.choice(vol_up_actions)
                emotion = rng.choice(["happy", "excited"])
            elif level <= 30:
                action = rng.choice(vol_down_actions)
                emotion = rng.choice(["normal", "happy", "curious"])
            else:
                action = rng.choice(vol_set_actions)
                emotion = rng.choice(["normal", "happy"])
            
            prefix = rng.choice(PREFIXES)
            user_text = (prefix + phrase).strip()
            samples.append(make_sample(user_text, action, emotion, cmd, base_speech))
    
    # Explicit numeric requests
    for level in range(0, 101, 5):
        phrases_for_level = [
            f"set volume to {level}",
            f"volume {level}",
            f"{level} percent volume",
            f"set it to {level}",
            f"volume at {level} percent",
            f"make it {level}",
            f"I want {level} percent volume",
        ]
        for phrase in rng.sample(phrases_for_level, min(4, len(phrases_for_level))):
            cmd = f'osascript -e "set volume output volume {level}"'
            action = rng.choice(vol_set_actions)
            emotion = rng.choice(["normal", "happy"])
            speech = rng.choice(["Volume set!", "Done!", "There you go!", "All adjusted!",
                                f"Volume at {level}.", "Got it!"])
            for prefix in rng.sample(PREFIXES, 2):
                user_text = (prefix + phrase).strip()
                samples.append(make_sample(user_text, action, emotion, cmd, speech))
    
    return samples


def generate_dark_light_samples(rng):
    """Generate expanded dark/light mode samples."""
    samples = []
    
    dark_cmd = "osascript -e 'tell app \"System Events\" to set dark mode of appearance preferences to true'"
    light_cmd = "osascript -e 'tell app \"System Events\" to set dark mode of appearance preferences to false'"
    
    dark_phrases = [
        "dark mode", "turn on dark mode", "switch to dark mode", "dark mode on",
        "enable dark mode", "make it dark", "go dark", "I want dark mode",
        "my eyes hurt from the brightness", "this screen is too bright at night",
        "night mode", "dark theme", "dark mode please", "dim everything",
        "switch to dark theme", "activate dark mode", "dark interface",
        "the screen is killing my eyes", "I need dark mode",
        "easier on the eyes please", "dark side please", "time for dark mode",
        "it's nighttime turn on dark mode", "I prefer dark mode", "can we go dark",
        "I always use dark mode", "dark mode is better", "switch to the dark side",
        "it's too bright", "my eyes need a break", "night theme",
    ]
    
    light_phrases = [
        "light mode", "turn on light mode", "switch to light mode", "light mode on",
        "enable light mode", "make it bright", "go light", "I want light mode",
        "bright mode", "light theme", "light mode please", "brighten it",
        "switch to light theme", "activate light mode", "day mode",
        "I can't see in dark mode", "turn off dark mode", "disable dark mode",
        "light interface", "it's daytime go light mode", "I prefer light mode",
        "back to light mode", "switch back to light", "the sun is out go light",
        "white mode", "bright theme", "regular mode",
    ]
    
    dark_speech = [
        "Going dark!", "Dark mode activated!", "Dimming things for you!",
        "Night vibes on!", "Easy on the eyes now!", "Dark mode is your friend.",
        "Switching to the dark side!", "Cozy darkness enabled!", "Dark theme on!",
        "Much better for nighttime!", "Dark and cozy!", "There, much easier to look at!",
    ]
    
    light_speech = [
        "Let there be light!", "Brightening things up!", "Light mode on!",
        "Sunshine mode activated!", "Back to the bright side!", "Light theme enabled!",
        "Bright and clear now!", "Everything is brighter now!", "Day mode on!",
        "Light and airy!", "Bright and beautiful!", "There you go, nice and bright!",
    ]
    
    dark_actions = ["pushWidget", "sitOnCorner", "idle", "tapWindow", "sit"]
    light_actions = ["wave", "spin", "idle", "jump", "tapWindow"]
    
    for phrase in dark_phrases:
        for _ in range(rng.randint(3, 6)):
            prefix = rng.choice(PREFIXES)
            user_text = (prefix + phrase).strip()
            action = rng.choice(dark_actions)
            emotion = rng.choice(["happy", "normal", "curious"])
            speech = rng.choice(dark_speech)
            samples.append(make_sample(user_text, action, emotion, dark_cmd, speech))
    
    for phrase in light_phrases:
        for _ in range(rng.randint(3, 6)):
            prefix = rng.choice(PREFIXES)
            user_text = (prefix + phrase).strip()
            action = rng.choice(light_actions)
            emotion = rng.choice(["happy", "normal", "excited"])
            speech = rng.choice(light_speech)
            samples.append(make_sample(user_text, action, emotion, light_cmd, speech))
    
    return samples


def generate_screenshot_samples(rng):
    """Generate expanded screenshot samples."""
    samples = []
    cmd = "screencapture ~/Desktop/screenshot.png"
    
    phrases = [
        "take a screenshot", "screenshot", "snap the screen", "capture the screen",
        "screen capture", "take a screen grab", "screenshot please", "screencap",
        "grab the screen", "snap it", "capture this", "screenshot this",
        "save the screen", "take a pic of the screen", "screen snap",
        "I need a screenshot", "can you screenshot", "get a screenshot",
        "capture my screen", "take a snap", "screenshot my screen",
        "screen shot please", "save what's on my screen", "snap this screen",
        "capture what I'm seeing", "I want a screenshot",
    ]
    
    speech = [
        "Screenshot captured!", "Saved to your Desktop!", "Got it! Captured and saved!",
        "Click! Screenshot taken!", "Screen captured for you!", "Snap! There it is!",
        "Picture taken!", "Your screen is saved!", "Captured! Check your Desktop!",
        "Done! Screenshot on your Desktop!", "Captured the moment!", "Saved!",
    ]
    
    actions = ["wave", "jump", "tapWindow", "spin", "idle", "backflip"]
    emotions = ["happy", "excited", "normal", "proud"]
    
    for phrase in phrases:
        for _ in range(rng.randint(4, 7)):
            prefix = rng.choice(PREFIXES)
            user_text = (prefix + phrase).strip()
            samples.append(make_sample(user_text, rng.choice(actions), rng.choice(emotions), cmd, rng.choice(speech)))
    
    return samples


def generate_sleep_samples(rng):
    """Generate expanded sleep Mac samples."""
    samples = []
    cmd = "pmset sleepnow"
    
    phrases = [
        "put the Mac to sleep", "sleep mode", "sleep", "put it to sleep",
        "goodnight Mac", "time to sleep", "nap time for the Mac",
        "send the Mac to sleep", "sleep the computer", "Mac sleep now",
        "power nap", "sleep mode please", "let the Mac rest", "sleepy time",
        "go to sleep Mac", "night night Mac", "let the computer rest",
        "I'm done for the night put it to sleep", "make the Mac sleep",
        "shutdown the display", "turn off the screen", "sleep the display",
        "Mac nap time", "I'm heading to bed put it to sleep",
    ]
    
    speech = [
        "Sweet dreams, Mac!", "Putting it to sleep now.", "Night night!",
        "Sleep mode activated!", "Time for a nap.", "Goodnight!",
        "Rest easy.", "Your Mac is going to sleep.", "Zzz... sleep mode on.",
        "Mac is going night-night!", "Nap time!", "Sweet digital dreams!",
    ]
    
    actions = ["sleep", "idle", "sitOnCorner", "sit", "wave", "bow"]
    emotions = ["sleepy", "normal", "happy", "love"]
    
    for phrase in phrases:
        for _ in range(rng.randint(4, 6)):
            prefix = rng.choice(PREFIXES)
            user_text = (prefix + phrase).strip()
            samples.append(make_sample(user_text, rng.choice(actions), rng.choice(emotions), cmd, rng.choice(speech)))
    
    return samples


def generate_contextual_samples(rng):
    """Generate context-driven CMD samples where the model infers the command."""
    samples = []
    
    # (context_format, app_key, speech_variations)
    scenarios = [
        # Work contexts → coding tools
        ("USER SAID: 'I have a bug to fix'. EMOTION: thinking.", "Xcode",
         ["Let's squash that bug!", "Debugging time!", "Let's find it and fix it!"]),
        ("USER SAID: 'need to push my changes'. EMOTION: normal.", "Terminal",
         ["Terminal's ready for git!", "Let's get those commits pushed!", "Shell's ready!"]),
        ("USER SAID: 'gotta write some Python'. EMOTION: normal.", "Visual Studio Code",
         ["Python time! Editor's loading!", "Let's write some Python!", "Your coding canvas awaits!"]),
        ("USER SAID: 'time to review the pull request'. EMOTION: thinking.", "Google Chrome",
         ["Let's review that PR!", "Browser's loading up for code review!", "Review mode on!"]),
        ("USER SAID: 'I need to deploy this'. EMOTION: normal.", "Terminal",
         ["Deploy time! Shell's ready!", "Let's ship it!", "Terminal launching for deployment!"]),
        
        # Communication contexts
        ("USER SAID: 'I should reply to that email'. EMOTION: normal.", "Mail",
         ["Let's get to that reply!", "Inbox loading!", "Time to respond!"]),
        ("USER SAID: 'the team is waiting for me'. EMOTION: normal.", "Slack",
         ["Let's not keep them waiting!", "Connecting to the team!", "Slack incoming!"]),
        ("USER SAID: 'my friend just messaged me'. EMOTION: happy.", "Messages",
         ["Let's see what they said!", "Opening your messages!", "Time to catch up!"]),
        ("USER SAID: 'I need to hop on a call'. EMOTION: normal.", "FaceTime",
         ["Video call loading!", "Connecting you now!", "Call's coming up!"]),
        
        # Planning contexts
        ("USER SAID: 'what do I have going on this week'. EMOTION: curious.", "Calendar",
         ["Let's check your schedule!", "Calendar loading!", "Let's see the week ahead!"]),
        ("USER SAID: 'I need to plan my tasks'. EMOTION: thinking.", "Reminders",
         ["Task planning mode!", "Let's get organized!", "Your to-do list awaits!"]),
        ("USER SAID: 'let me write down this idea'. EMOTION: excited.", "Notes",
         ["Capture that idea!", "Notes ready for brilliance!", "Let's save that thought!"]),
        
        # Entertainment contexts
        ("USER SAID: 'I'm bored'. EMOTION: bored.", "Spotify",
         ["Let me put on some tunes!", "Music fixes boredom!", "Let's vibe!"]),
        ("USER SAID: 'the silence is killing me'. EMOTION: bored.", "Music",
         ["Let's break the silence!", "Music incoming!", "No more silence!"]),
        ("USER SAID: 'I want to relax'. EMOTION: normal.", "Podcasts",
         ["Podcast and chill!", "Let's listen to something relaxing!", "Relaxation mode!"]),
        
        # Utility contexts
        ("USER SAID: 'where did I save that file'. EMOTION: curious.", "Finder",
         ["Let's find it!", "File hunt begins!", "Finder to the rescue!"]),
        ("USER SAID: 'I need to calculate something'. EMOTION: thinking.", "Calculator",
         ["Math time!", "Crunching numbers!", "Calculator at your service!"]),
        ("USER SAID: 'should I bring an umbrella'. EMOTION: curious.", "Weather",
         ["Let's check the forecast!", "Weather report incoming!", "Let me check!"]),
        ("USER SAID: 'I want to see vacation pics'. EMOTION: love.", "Photos",
         ["Photo memories incoming!", "Let's revisit those moments!", "Memory lane awaits!"]),
        ("USER SAID: 'my Mac feels slow'. EMOTION: curious.", "Activity Monitor",
         ["Let's see what's going on!", "Diagnostics mode!", "Checking system activity!"]),
        ("USER SAID: 'I need to update some apps'. EMOTION: normal.", "App Store",
         ["App Store loading!", "Let's get those updates!", "Update time!"]),
        ("USER SAID: 'I need to change my wallpaper'. EMOTION: curious.", "System Settings",
         ["Settings loading!", "Let's customize!", "Personalization time!"]),
    ]
    
    for ctx, app_key, speech_list in scenarios:
        info = APPS.get(app_key)
        if not info:
            continue
        cmd, _, actions, emotions = info
        
        for _ in range(rng.randint(12, 20)):
            action = rng.choice(actions)
            emotion = rng.choice(emotions)
            speech = rng.choice(speech_list)
            samples.append(make_ctx_sample(ctx, action, emotion, cmd, speech))
    
    return samples


def main():
    output_dir = os.path.dirname(os.path.abspath(__file__))
    train_path = os.path.join(output_dir, "train.jsonl")
    test_path = os.path.join(output_dir, "test.jsonl")
    valid_path = os.path.join(output_dir, "valid.jsonl")
    
    rng = random.Random(777)
    
    print("Generating supplemental CMD samples...")
    
    app_samples = generate_app_samples(rng)
    print(f"  App open samples: {len(app_samples)}")
    
    vol_samples = generate_volume_samples(rng)
    print(f"  Volume samples:   {len(vol_samples)}")
    
    dl_samples = generate_dark_light_samples(rng)
    print(f"  Dark/light mode:  {len(dl_samples)}")
    
    ss_samples = generate_screenshot_samples(rng)
    print(f"  Screenshot:       {len(ss_samples)}")
    
    sleep_samples = generate_sleep_samples(rng)
    print(f"  Sleep Mac:        {len(sleep_samples)}")
    
    ctx_samples = generate_contextual_samples(rng)
    print(f"  Contextual:       {len(ctx_samples)}")
    
    all_samples = app_samples + vol_samples + dl_samples + ss_samples + sleep_samples + ctx_samples
    rng.shuffle(all_samples)
    total = len(all_samples)
    print(f"\nTotal supplemental samples: {total}")
    
    # Split: 95% train, 2.5% test, 2.5% valid
    test_count = max(1, int(total * 0.025))
    valid_count = max(1, int(total * 0.025))
    
    train_samples = all_samples[:total - test_count - valid_count]
    test_samples = all_samples[total - test_count - valid_count:total - valid_count]
    valid_samples = all_samples[total - valid_count:]
    
    print(f"  Train: {len(train_samples)}")
    print(f"  Test:  {len(test_samples)}")
    print(f"  Valid: {len(valid_samples)}")
    
    # Append
    for path, samp, label in [
        (train_path, train_samples, "train"),
        (test_path, test_samples, "test"),
        (valid_path, valid_samples, "valid"),
    ]:
        with open(path, "a", encoding="utf-8") as f:
            for s in samp:
                f.write(json.dumps(s, ensure_ascii=False) + "\n")
        print(f"  Appended {len(samp)} to {label}.jsonl")
    
    # Final stats
    print("\n--- Final Dataset Stats ---")
    import re
    with open(train_path) as f:
        lines = f.readlines()
    total_train = len(lines)
    cmd_none = 0
    cmd_real = 0
    for line in lines:
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
    
    print(f"Total train.jsonl: {total_train}")
    print(f"  CMD: none = {cmd_none} ({100*cmd_none/total_train:.1f}%)")
    print(f"  CMD: real = {cmd_real} ({100*cmd_real/total_train:.1f}%)")
    print(f"  No CMD    = {total_train - cmd_none - cmd_real}")
    print(f"  CMD real% = {100*cmd_real/(cmd_none+cmd_real):.1f}% of tagged samples")


if __name__ == "__main__":
    main()
