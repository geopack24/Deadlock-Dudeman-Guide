# DUDELOCK LOBBY PROBE  (read-only diagnostic)
# ============================================
# One question: does Deadlock's own console.log name ALL TWELVE heroes in a
# match? If it does, a small watcher can fill the counterpicker automatically
# and share the comp with the whole party. If it only ever names your own hero,
# the screenshot scanner stays the best tool and we stop chasing this.
#
# (Statlocker Companion was already ruled out as a source: it reads the game's
# memory rather than any log, exposes no local port, and never persists the
# lobby - so there is nothing there for us to read.)
#
# SETUP, once:
#   Steam > right-click Deadlock > Properties > Launch Options, add:  -condebug
#   Then play one REAL match (not sandbox/bots - those log differently).
#
# Then run this and send the output. It changes nothing; it only reads.

$ErrorActionPreference = 'SilentlyContinue'
function Note($t) { Write-Host "    $t" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '  DUDELOCK LOBBY PROBE' -ForegroundColor Cyan
Write-Host '  --------------------' -ForegroundColor DarkCyan

# locate Deadlock across all Steam libraries
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
  Write-Host ''
  Write-Host '  Deadlock not found in any Steam library.' -ForegroundColor Red
  Note 'Find console.log by hand and search it for: Loaded hero'
  Read-Host '  Press Enter to close'; exit
}
Write-Host ''
Write-Host "  Install: $game" -ForegroundColor Green

$logs = Get-ChildItem -Path $game -Recurse -Filter 'console.log' | Sort-Object LastWriteTime -Descending
if (-not $logs) {
  Write-Host '  NO console.log FOUND.' -ForegroundColor Red
  Note '-condebug is not set. Add it to the launch options (see the top of this'
  Note 'file), play a match, then run this again.'
  Read-Host '  Press Enter to close'; exit
}

$log = $logs[0]
Write-Host ("  Log: {0}" -f $log.FullName) -ForegroundColor Green
Write-Host ("       {0:N0} KB, last written {1}" -f ($log.Length/1KB), $log.LastWriteTime)
$txt = Get-Content $log.FullName
Write-Host "       $($txt.Count) lines"

# ---- THE DECISIVE TEST: how many DISTINCT heroes does the log name? ----
$heroes = @{}
$txt | Select-String -Pattern 'hero_[a-z0-9_]+' -AllMatches | ForEach-Object {
  $_.Matches | ForEach-Object { $heroes[$_.Value.ToLower()] = $true }
}
Write-Host ''
Write-Host '  =========================================================' -ForegroundColor Yellow
Write-Host ("   DISTINCT hero_* names in this log: {0}" -f $heroes.Count) -ForegroundColor Cyan
if ($heroes.Count -ge 10) {
  Write-Host '   >>> A FULL LOBBY LOOKS RECOVERABLE - this is buildable. <<<' -ForegroundColor Green
} elseif ($heroes.Count -ge 1) {
  Write-Host '   >>> Only a few named - likely just your hero. Probably dead. <<<' -ForegroundColor DarkYellow
} else {
  Write-Host '   >>> No hero names at all in the log. <<<' -ForegroundColor Red
}
Write-Host '  =========================================================' -ForegroundColor Yellow
if ($heroes.Count) { Note (($heroes.Keys | Sort-Object) -join ', ') }

Write-Host ''
Write-Host '  Lines naming a hero (last 25) - I need to see their shape:' -ForegroundColor Cyan
$txt | Select-String -Pattern 'hero_[a-z0-9_]+' | Select-Object -Last 25 |
  ForEach-Object { Note ($_.Line.Trim() -replace '\s+',' ') }

Write-Host ''
Write-Host '  Lobby / game-coordinator lines (last 20):' -ForegroundColor Cyan
$gc = $txt | Select-String -Pattern 'CMsgGC|Lobby \d+|Precaching \d+ heroes|Players:\s+\d+|Loaded hero'
if ($gc) { $gc | Select-Object -Last 20 | ForEach-Object { Note ($_.Line.Trim() -replace '\s+',' ') } }
else { Note '(none found)' }

Write-Host ''
Write-Host '  Done - copy everything above and send it over.' -ForegroundColor Cyan
Write-Host ''
Read-Host '  Press Enter to close'
