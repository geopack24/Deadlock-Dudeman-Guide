# DUDELOCK LOBBY PROBE  (read-only diagnostic)
# ============================================
# One question, and the whole auto-fill idea rests on it:
#
#   Does Deadlock's console.log name all TWELVE heroes AT MATCH START?
#
# If yes, a small watcher can fill the counterpicker the moment a match loads
# and share it with the party. If the log only ever names your own hero, we drop
# the idea and the screenshot scanner stays the best tool.
#
# Statlocker Companion is already ruled out as a source - it reads the game's
# memory, exposes no local port, and never saves the lobby anywhere.
#
# SETUP, once:
#   Steam > right-click Deadlock > Properties > Launch Options, add:  -condebug
#   Play one REAL match (not sandbox/bots - those load differently).
#   Running it while still in the match is ideal - that proves the timing.
#
# Reads only. Changes nothing.

$ErrorActionPreference = 'SilentlyContinue'
function Note($t) { Write-Host "    $t" -ForegroundColor DarkGray }
function Head($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan }

Write-Host ''
Write-Host '  DUDELOCK LOBBY PROBE' -ForegroundColor Cyan
Write-Host '  --------------------' -ForegroundColor DarkCyan

# ---- locate Deadlock ----
$libs = @('C:\Program Files (x86)\Steam')
$vdf = 'C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf'
if (Test-Path $vdf) {
  Get-Content $vdf | Select-String '"path"' | ForEach-Object {
    $libs += ($_ -replace '.*"path"\s*"([^"]+)".*','$1') -replace '\\\\','\'
  }
}
$game = $null
foreach ($l in ($libs | Select-Object -Unique)) {
  $c = Join-Path $l 'steamapps\common\Deadlock'
  if (Test-Path $c) { $game = $c; break }
}
if (-not $game) {
  Write-Host ''; Write-Host '  Deadlock not found in any Steam library.' -ForegroundColor Red
  Note 'Find console.log by hand and search it for:  models/heroes'
  Read-Host '  Press Enter to close'; exit
}
Write-Host ''
Write-Host "  Install: $game" -ForegroundColor Green

$logs = Get-ChildItem -Path $game -Recurse -Filter 'console.log' | Sort-Object LastWriteTime -Descending
if (-not $logs) {
  Write-Host '  NO console.log FOUND.' -ForegroundColor Red
  Note '-condebug is not set. Add it to the launch options (see top of this file),'
  Note 'play a match, then run this again.'
  Read-Host '  Press Enter to close'; exit
}
$log = $logs[0]
Write-Host ("  Log: {0}" -f $log.FullName) -ForegroundColor Green
Write-Host ("       {0:N0} KB, last written {1}" -f ($log.Length/1KB), $log.LastWriteTime)
$txt = Get-Content $log.FullName
Write-Host "       $($txt.Count) lines"

# ---- find where the most recent match started, so we can judge TIMING ----
$startIdx = 0
for ($i = $txt.Count - 1; $i -ge 0; $i--) {
  if ($txt[$i] -match 'Precaching \d+ heroes|Lobby \d+ for Match \d+ created|CL: Connected to') { $startIdx = $i; break }
}
if ($startIdx -gt 0) {
  Write-Host ''
  Write-Host ("  Most recent match-start marker at line {0}:" -f $startIdx) -ForegroundColor Green
  Note ($txt[$startIdx].Trim() -replace '\s+',' ')
}

# ---- hero names, BOTH forms ----
# form A: hero_<name>   (server-side "Loaded hero", GC messages)
# form B: models/heroes[_wip|_staging]/<name>/   (CLIENT-side model loads - the
#         one that actually fires at match load, and has no hero_ prefix)
function HeroSet($lines) {
  $set = @{}
  $lines | Select-String -Pattern 'hero_[a-z0-9]+' -AllMatches | ForEach-Object {
    $_.Matches | ForEach-Object { $set[($_.Value.ToLower() -replace '^hero_','')] = $true }
  }
  $lines | Select-String -Pattern 'models/heroes(?:_wip|_staging)?/([a-z0-9_]+)/' -AllMatches | ForEach-Object {
    $_.Matches | ForEach-Object { $set[$_.Groups[1].Value.ToLower()] = $true }
  }
  # strip obvious non-hero tokens
  'generic','base','template','dummy','test' | ForEach-Object { $set.Remove($_) }
  return $set
}

$allSet   = HeroSet $txt
$sinceSet = if ($startIdx -gt 0) { HeroSet ($txt[$startIdx..($txt.Count-1)]) } else { $allSet }

Write-Host ''
Write-Host '  =============================================================' -ForegroundColor Yellow
Write-Host ("   DISTINCT heroes in whole log      : {0}" -f $allSet.Count) -ForegroundColor Cyan
Write-Host ("   DISTINCT heroes SINCE match start : {0}   <-- the number that matters" -f $sinceSet.Count) -ForegroundColor Cyan
Write-Host '  =============================================================' -ForegroundColor Yellow
if ($sinceSet.Count -ge 10) {
  Write-Host '   >>> A FULL LOBBY IS IN THE LOG AT MATCH START. BUILDABLE. <<<' -ForegroundColor Green
} elseif ($allSet.Count -ge 10) {
  Write-Host '   >>> All 12 appear somewhere, but not clearly at match start -' -ForegroundColor DarkYellow
  Write-Host '       send the output anyway, the timing may still work. <<<' -ForegroundColor DarkYellow
} else {
  Write-Host '   >>> Not enough heroes named - this route is probably dead. <<<' -ForegroundColor Red
}
if ($sinceSet.Count) { Note (($sinceSet.Keys | Sort-Object) -join ', ') }

Head 'Client-side hero model loads (last 20) - the best signal:'
$vm = $txt | Select-String -Pattern 'models/heroes(?:_wip|_staging)?/[a-z0-9_]+/'
if ($vm) { $vm | Select-Object -Last 20 | ForEach-Object { Note ($_.Line.Trim() -replace '\s+',' ') } } else { Note '(none)' }

Head 'Server-side "Loaded hero" lines (last 15):'
$lh = $txt | Select-String -Pattern 'Loaded hero'
if ($lh) { $lh | Select-Object -Last 15 | ForEach-Object { Note ($_.Line.Trim() -replace '\s+',' ') } } else { Note '(none - expected on dedicated servers)' }

Head 'Lobby / precache / GC lines (last 20):'
$gc = $txt | Select-String -Pattern 'CMsgGC|Lobby \d+|Precaching \d+ heroes|Players:\s+\d+'
if ($gc) { $gc | Select-Object -Last 20 | ForEach-Object { Note ($_.Line.Trim() -replace '\s+',' ') } } else { Note '(none)' }

Write-Host ''
Write-Host '  Done - copy everything above and send it over.' -ForegroundColor Cyan
Write-Host ''
Read-Host '  Press Enter to close'
