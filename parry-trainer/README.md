# Dudelock Parry Trainer

Trains the one thing you can't practice in a real match: hearing the heavy-melee
cue and parrying on reflex, without parrying at every other sound.

It plays the cue at random intervals (5–30s by default), and grades you — even
while Deadlock is the focused window.

## Run it

1. Download this folder (Code → Download ZIP, or clone) and unzip it.
2. Double-click **`Parry Trainer.bat`**.
3. Press your parry key when it asks, so it knows what to listen for.
4. Press Enter to start, then **alt-tab into Deadlock's sandbox** and mess around.
5. Hit your parry key **only** when you hear the heavy cue.
6. Hold **Esc** to stop and see your numbers.

No installs. No admin. Works on any Windows machine — it's a PowerShell script
using built-in Windows calls.

> If Windows SmartScreen complains about the `.bat`, it's because the file came
> from the internet: right-click → Properties → Unblock, or run the `.ps1`
> directly with `powershell -ExecutionPolicy Bypass -File parry_trainer.ps1`.

## What it measures

| Result | Meaning |
| --- | --- |
| **PARRIED** | You hit it inside the window — logs your reaction time in ms |
| **MISSED** | Heavy cue played, no parry in time |
| **BAITED** | You parried a *light* melee decoy — the habit that gets you killed |
| **early** | You parried with no cue at all — spam, punished in real games |

At the end you get best / median / average reaction time. For reference, human
audio reaction time is usually 150–250 ms; anything under 250 ms average is
genuinely quick.

## Settings

Press `s` at the menu:

- **Interval** — shortest and longest gap between cues (default 5–30s). Keep it
  long and irregular; predictable timing trains the wrong thing.
- **Window** — how long after the cue still counts (default 600 ms). Tighten it
  toward 400 ms as you improve.
- **Decoys** — light-melee cues you must ignore (default on). Turn them off only
  for your first session.

Saved to `parry_config.json` next to the script.

## Using the real game audio

The included `heavy_melee.wav` and `light_melee.wav` are synthesized stand-ins so
the tool works immediately. Training against the **actual** sound is better —
that's the cue your ears need to learn.

Replace the files with the real ones, keeping the same names (16-bit PCM WAV):

- Record it: run Deadlock's sandbox, heavy melee, and capture with any recorder
  (Audacity, Windows Game Bar, OBS), then trim to just the wind-up and save as WAV.
- Or extract from the game files with a Source 2 VPK tool.

Anything that plays in Windows Media Player as a WAV will work here.

## Why it isn't just a page on the site

A browser can't read your keyboard while another program has focus — that's a
hard security boundary, not something a page can opt out of. Playing sound while
unfocused works fine; detecting the parry doesn't. So the cue *and* the scoring
live here, in a local script that asks Windows directly.
