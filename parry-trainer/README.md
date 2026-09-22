# Dudelock Parry Trainer

Trains the one thing you can't drill in a real match: hearing the heavy-melee
cue and parrying on reflex.

It plays the real heavy-melee sound at random intervals (5–30s by default) and
grades you with an instant good/bad sound — so you never have to look at the
window while you play. It keeps listening **while Deadlock is the focused
application**.

## Run it

1. Download this folder (Code → Download ZIP, or clone) and unzip it.
2. Double-click **`Parry Trainer.bat`**.
3. Press your parry key when it asks, so it knows what to listen for.
4. Press Enter to start, then **alt-tab into Deadlock's sandbox** and mess around.
5. Parry when you hear the heavy melee.
6. Hold **Esc** to stop and see your numbers.

No installs. No admin. Works on any Windows machine — it's a PowerShell script
using built-in Windows calls.

> If Windows SmartScreen complains about the `.bat`, it's because the file came
> from the internet: right-click → Properties → Unblock, or run the `.ps1`
> directly with `powershell -ExecutionPolicy Bypass -File parry_trainer.ps1`.

## What you'll hear

| Sound | Meaning |
| --- | --- |
| Heavy melee | The cue — parry now |
| **Rising chime** | Parried in time (reaction time logged) |
| **Low buzz** | Missed the window, or parried with no cue at all |

The feedback sound cuts the cue short, which is intentional — the moment has
resolved, and you get an unambiguous answer without alt-tabbing.

Turn feedback off in settings if you'd rather train silent.

## What it measures

- **PARRIED** — inside the window, with your reaction time in ms
- **MISSED** — cue played, no parry in time
- **early** — parried with nothing on screen; the spam habit that gets punished

At the end you get best / median / average. For reference, human audio reaction
time is usually 150–250 ms; under 250 ms average is genuinely quick.

Reaction times are honest — the script asks Windows for 1 ms timer resolution
(the default is ~15 ms, which would smear every measurement).

## Settings

Press `s` at the menu:

- **Interval** — shortest and longest gap between cues (default 5–30s). Keep it
  long and irregular; predictable timing trains the wrong thing.
- **Window** — how long after the cue still counts (default 600 ms). Tighten it
  toward 400 ms as you improve.
- **Feedback** — the good/bad sounds (default on).

Saved to `parry_config.json` next to the script.

## The sounds

`heavy_melee.wav` is the real in-game heavy-melee audio, trimmed to its exact
onset (the source recording had ~260 ms of noise floor in front of it, which
would have made every cue feel late and inflated every reaction time) and
normalized so it cuts through game audio.

`good.wav` and `bad.wav` are synthesized feedback tones, deliberately unlike
anything in Deadlock so they can't be confused with a real game sound.

To swap any of them, replace the file with a 16-bit PCM WAV of the same name.

## Why it isn't just a page on the site

A browser can't read your keyboard while another program has focus — that's a
hard security boundary, not something a page can opt out of. Playing sound while
unfocused works fine; detecting the parry doesn't. So the cue *and* the scoring
live here, in a local script that asks Windows directly.
