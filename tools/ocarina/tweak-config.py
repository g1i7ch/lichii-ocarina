#!/usr/bin/env python3
"""Config tweaks for Lichii's qt-config.ini. Run while the emulator is NOT running (it rewrites the
ini on exit). The ini marks each setting with `key\\default=true|false`; with true the emulator ignores
the value line and uses its built-in default, so every tweak sets the flag to false as well.

  --vsync-mailbox  use_vsync 2 (FIFO) -> 1 (Mailbox). Inside gamescope FIFO at a 120 Hz nested refresh
                   snaps the frame rate to 120/n (60, 40, 30); Mailbox lets the game's own 60 Hz vsync
                   event pace it and gamescope composites, so no tearing.
  --gpu-fast       gpu_accuracy -> 0 (Fast/Low). The GPU thread split (front/back threads) only runs in
                   this mode; with High the emulator logs no split and runs one GPU thread.
"""
import re, sys, pathlib

def set_key(text, section, key, value):
    sec_re = re.compile(r"(?ms)^\[" + re.escape(section) + r"\]\n(.*?)(?=^\[|\Z)")
    m = sec_re.search(text)
    if not m:
        return text + f"\n[{section}]\n{key}\\default=false\n{key}={value}\n", True
    body = m.group(1)
    new = re.sub(r"(?m)^" + re.escape(key) + r"\\default=.*$", f"{key}\\\\default=false", body)
    if new == body:
        new = f"{key}\\default=false\n" + new
    if re.search(r"(?m)^" + re.escape(key) + r"=", new):
        new2 = re.sub(r"(?m)^" + re.escape(key) + r"=.*$", f"{key}={value}", new)
    else:
        new2 = new + f"{key}={value}\n"
    changed = new2 != body
    return text[:m.start(1)] + new2 + text[m.end(1):], changed

args = [a for a in sys.argv[1:] if a.startswith("--")]
paths = [a for a in sys.argv[1:] if not a.startswith("--")]
ini = pathlib.Path(paths[0] if paths else "build/bin/user/config/qt-config.ini")
text = ini.read_text()
for flag, (sec, key, val) in {"--vsync-mailbox": ("Renderer", "use_vsync", "1"),
                              "--gpu-fast": ("Renderer", "gpu_accuracy", "0")}.items():
    if flag in args:
        text, changed = set_key(text, sec, key, val)
        print(f"{ini}: {key}={val} ({'changed' if changed else 'already set'})")
ini.write_text(text)
