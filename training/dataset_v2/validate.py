"""Checks a training reply against what the app can actually use.

Valid actions/emotions are read from the Swift source so the dataset can't drift from
the app, and CMD strings go through the same rules as AIEngine.parseAllowedCommand().
"""
import os
import re
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _enum_cases(swift_file: str, enum: str) -> set:
    src = open(os.path.join(ROOT, "DesktopPet", swift_file)).read()
    body = re.search(r"enum %s: String \{(.*?)\n\}" % enum, src, re.S).group(1)
    body = body.split("static func")[0]          # skip helper methods
    return {name for line in re.findall(r"^\s*case (.+)$", body, re.M) for name in re.findall(r"\w+", line)}


ACTIONS = _enum_cases("PetBrain.swift", "PetAction")
EMOTIONS = _enum_cases("PetBrain.swift", "PetEmotion") | {
    # Extra words PetEmotion.fromModelTag() maps onto a face.
    "calm", "quiet", "cozy", "coffee", "working", "focused", "empathetic", "cold",
    "dj", "hyped", "surprised", "batterylow", "tired", "loving", "grateful"}

# Speech may be empty: staying quiet (on a call, mid-focus) is a valid reply.
REPLY = re.compile(r"^\[ACTION: (\w+)\] \[EMOTION: (\w+)\] \[CMD: ([^\]]+)\](?: (\S.*))?$")
APP_NAME = re.compile(r"^[A-Za-z0-9 ._-]{1,40}$")


def _tokenize(line: str) -> list:
    tokens, cur, quote, in_tok = [], "", None, False
    for ch in line:
        if quote:
            if ch == quote:
                quote = None
            else:
                cur += ch
        elif ch in "\"'":
            quote, in_tok = ch, True
        elif ch.isspace():
            if in_tok:
                tokens.append(cur)
                cur, in_tok = "", False
        else:
            cur += ch
            in_tok = True
    if in_tok:
        tokens.append(cur)
    return tokens


def _web_url(s: str) -> bool:
    u = urlparse(s)
    return u.scheme in ("http", "https") and bool(u.netloc)


def command_allowed(cmd: str) -> bool:
    """Python port of AIEngine.parseAllowedCommand (keep the two in sync)."""
    cmd = cmd.strip()
    if not cmd or cmd.lower() == "none" or len(cmd) >= 300:
        return False
    t = _tokenize(cmd)
    head, args = t[0].lower(), t[1:]
    if head == "open":
        return ((len(args) == 2 and args[0] == "-a" and APP_NAME.match(args[1]) is not None)
                or (len(args) == 1 and _web_url(args[0]))
                or (len(args) == 3 and args[0] == "-a" and APP_NAME.match(args[1]) is not None and _web_url(args[2])))
    if head == "screencapture":
        return True
    if head == "pmset":
        return [a.lower() for a in args] in (["sleepnow"], ["displaysleepnow"])
    if head == "osascript":
        if len(t) != 3 or t[1] != "-e":
            return False
        s = t[2].strip().lower()
        volume = re.sub(r'^tell app(lication)? "system events" to ', "", s)   # same as the Swift parser
        return bool(re.fullmatch(r"set volume output volume \d{1,3}", volume)
                    or s in ("set volume with output muted true", "set volume with output muted false")
                    or re.fullmatch(r'tell app(lication)? "system events" to set dark mode of appearance preferences to (true|false)', s))
    if head == "mdfind":
        q = " ".join(args).strip()
        return 1 <= len(q) <= 100 and not q.startswith("-")
    return False


def check_reply(reply: str) -> str:
    """Returns "" if the reply is usable, otherwise why not."""
    m = REPLY.match(reply)
    if not m:
        return "format"
    action, emotion, cmd, speech = m.groups()
    speech = speech or ""
    if action not in ACTIONS:
        return f"action:{action}"
    if emotion.lower() not in {e.lower() for e in EMOTIONS}:
        return f"emotion:{emotion}"
    if cmd.strip().lower() != "none" and not command_allowed(cmd):
        return "cmd"
    words = len(speech.split())
    if words > 18:
        return "long"
    if re.search(r"\bByte (is|was|thinks|will|feels|wants)\b", speech):
        return "third-person"
    if re.search(r"[\U0001F300-\U0001FAFF]", speech):
        return "emoji"
    return ""
