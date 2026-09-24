# DUDELOCK tools

Small Windows helpers. No install, no Python — just PowerShell, which every Windows PC has.

## Lobby Watcher — auto-fill the counterpicker from the game

`Lobby Watcher.bat` tails Deadlock's console log while you play. When a match
starts it publishes what it can see (your hero, the map, every hero the log
names) to the shared DUDELOCK lobby feed, and the site shows a **⚡ LIVE LOBBY**
banner with one-click apply.

1. Steam → right-click Deadlock → **Properties** → **Launch Options** → add `-condebug`
2. Download this `tools` folder (or the whole repo zip), double-click **Lobby Watcher.bat**, leave it open
3. Play. Open the site; the banner appears when the match loads.

Works for anyone in the party — only one person needs to run it.

Honest status: match start/end, map, match id and **your own hero** are proven.
Whether the log names the **other 11 heroes and their teams** is still being
confirmed — the watcher harvests every hero it can and writes `lobby-debug.txt`
next to itself during the first minutes of a match. After a match, send that
file over so the parser can be tuned.

Replay a saved log without playing:

    powershell -ExecutionPolicy Bypass -File lobby-watcher.ps1 -Replay "C:\path\to\console.log"

## Lobby Probe — one-shot diagnostic

`Lobby Probe.bat` reads the log once and reports the last map, head count and
hero names it found. Use it to check whether a log is from a real match or just
the hideout.
