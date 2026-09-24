# DUDELOCK LOBBY WATCHER
# =======================
# Tails Deadlock's console.log (needs the -condebug launch option), notices when
# a match starts, works out which hero YOU picked and every hero the log names
# after that, and publishes the lot to the shared DUDELOCK lobby bin. The site
# polls that bin and offers to fill the counterpicker with one click.
#
# What is PROVEN (three independent Discord rich-presence tools rely on it):
#   - match start / end, map, match id, game phase      (ChangeGameState, Lobby ... created)
#   - YOUR hero                                         (VMDL Camera Pose Success!)
# What is UNVERIFIED until we see a real-match log:
#   - whether the other 11 heroes are named at all, and which team they are on.
#     Every hero-ish token after match start is harvested anyway, unknown tokens
#     are reported, and lobby-debug.txt captures the relevant lines so the first
#     real match can tune this file. Send that debug file over after a match.
#
# SETUP, once:   Steam > right-click Deadlock > Properties > Launch Options:  -condebug
# RUN:           double-click "Lobby Watcher.bat" before (or during) a match. Leave it open.
#
# Replay a saved log without tailing:   powershell -File lobby-watcher.ps1 -Replay "C:\path\console.log"
# (replay never publishes unless you add -Publish)

param(
  [string]$LogPath = '',
  [string]$Replay = '',
  [switch]$Publish,
  [switch]$NoPublish
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BIN  = '6ab518a3ffd5d160532a5ec9'
$KEY  = '$2a$10$xN0NFn7iLT2QLN3kjweAZOo5K77sve8wvXkOJ3JnALA9bmbYScUMS'   # same key the site already ships in its source
$VER  = 'watcher 1.2'
$DebugFile = Join-Path $PSScriptRoot 'lobby-debug.txt'

# internal class name -> display name (api.deadlock-api.com/v1/assets/heroes, Sep 2026)
$HERO = @{
  inferno='Infernus'; gigawatt='Seven'; hornet='Vindicta'; ghost='Lady Geist'; atlas='Abrams'
  wraith='Wraith'; forge='McGinnis'; chrono='Paradox'; dynamo='Dynamo'; kelvin='Kelvin'
  haze='Haze'; astro='Holliday'; bebop='Bebop'; nano='Calico'; orion='Grey Talon'
  krill='Mo & Krill'; shiv='Shiv'; tengu='Ivy'; warden='Warden'; yamato='Yamato'
  lash='Lash'; viscous='Viscous'; synth='Pocket'; mirage='Mirage'; viper='Vyper'
  magician='Sinclair'; vampirebat='Mina'; drifter='Drifter'; priest='Venator'; frank='Victor'
  bookworm='Paige'; doorman='The Doorman'; punkgoat='Billy'; necro='Graves'; fencer='Apollo'
  familiar='Rem'; werewolf='Silver'; unicorn='Celeste'
}
# model-folder names that differ from the class name
$ALIAS = @{ digger='krill'; gigawatt_prisoner='gigawatt'; vyper='viper' }
$IGNORE = @('builds','generic','base','shared','common','dummy','test','target','npc','template','placeholder','proxy')
$HIDEOUT = @('dl_hideout','hideout','new_player_basics')

# ---- state ----
$S = @{
  tracking=$false; phase='idle'; map=$null; matchId=$null; players=0; myHero=$null; who=$env:USERNAME
  heroes=New-Object System.Collections.Specialized.OrderedDictionary
  unknown=@{}; dirty=$false; lastPub=[DateTime]::MinValue; started=$null; debugLines=0
}

function Norm([string]$raw) {
  $k = $raw.ToLower()
  $k = $k -replace '_v\d+$',''
  if ($ALIAS.ContainsKey($k)) { $k = $ALIAS[$k] }
  return $k
}
function AddHero([string]$raw) {
  $k = Norm $raw
  if ($HERO.ContainsKey($k)) {
    if (-not $S.heroes.Contains($k)) { $S.heroes[$k] = $HERO[$k]; $S.dirty = $true; Write-Host ("    + {0}" -f $HERO[$k]) -ForegroundColor Green }
  } elseif ($IGNORE -notcontains $k -and $k -notmatch '^\d+$') {
    if (-not $S.unknown.ContainsKey($k)) { $S.unknown[$k] = 0 }
    $S.unknown[$k]++
  }
}
function StartMatch([string]$why) {
  if ($S.tracking) { return }
  # the hideout runs its own local server and walks the same game states - never treat that as a match
  if ($why -notlike 'map*' -and $HIDEOUT -contains $S.map) { return }
  $S.tracking = $true; $S.phase = 'starting'; $S.heroes.Clear(); $S.unknown = @{}; $S.myHero = $null
  $S.started = Get-Date; $S.dirty = $true; $S.debugLines = 0; $S.liveAt = $null
  try { Set-Content -Path $DebugFile -Value ("# DUDELOCK lobby debug - match started {0} ({1})" -f (Get-Date), $why) -Encoding UTF8 } catch {}
  Write-Host ''; Write-Host ("  >> MATCH TRACKING ON  ({0})" -f $why) -ForegroundColor Cyan
}
function EndMatch([string]$why) {
  if (-not $S.tracking) { return }
  $S.tracking = $false; $S.phase = 'ended'; $S.dirty = $true
  Write-Host ("  << match over ({0}) - {1} heroes seen" -f $why, $S.heroes.Count) -ForegroundColor DarkCyan
}
function Payload {
  $names = @($S.heroes.Values)
  $keys  = @($S.heroes.Keys)
  $unk   = @($S.unknown.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $_.Key })
  return @{
    v=1; src=$VER; ts=[int64]((Get-Date).ToUniversalTime() - [DateTime]'1970-01-01').TotalMilliseconds
    phase=$S.phase; map=$S.map; matchId=$S.matchId; players=$S.players
    who=$S.who; myHero=$S.myHero; heroes=$names; keys=$keys; unknown=$unk; liveAt=$S.liveAt
  }
}
function WhoKey { $k = ("{0}" -f $S.who) -replace '[^\w\- ]','' ; $k = $k.Trim(); if (-not $k) { $k = 'player' }; if ($k.Length -gt 32) { $k = $k.Substring(0,32) }; return $k }
function CurlExe { return (Get-Command curl.exe -ErrorAction SilentlyContinue) }
function ReadFeed {
  # the feed is one record holding a slot per person: { v:2, lobbies: { "<who>": payload } }
  try {
    $curl = CurlExe
    if ($curl) { $raw = & $curl.Source -s -m 20 "https://api.jsonbin.io/v3/b/$BIN/latest" 2>$null }
    else { $raw = (Invoke-WebRequest -UseBasicParsing -Uri "https://api.jsonbin.io/v3/b/$BIN/latest" -TimeoutSec 30).Content }
    if (-not $raw) { return $null }
    $rec = ($raw | ConvertFrom-Json).record
    $lob = @{}
    if ($rec -and $rec.lobbies) { foreach ($pr in $rec.lobbies.PSObject.Properties) { $lob[$pr.Name] = $pr.Value } }
    return $lob
  } catch { return $null }
}
function PublishNow {
  $p = Payload
  $lob = ReadFeed
  if ($lob -eq $null) { $S.lastPub = Get-Date; Write-Host '  publish skipped: could not read the feed (JSONBin slow?) - retrying shortly' -ForegroundColor Red; return }
  # drop other people's entries older than 6 h so the record never grows
  $nowMs = [int64]((Get-Date).ToUniversalTime() - [DateTime]'1970-01-01').TotalMilliseconds
  foreach ($k in @($lob.Keys)) { try { if (($nowMs - [int64]$lob[$k].ts) -gt 21600000) { $lob.Remove($k) } } catch { $lob.Remove($k) } }
  $lob[(WhoKey)] = $p
  $json = @{ v=2; ts=$nowMs; lobbies=$lob } | ConvertTo-Json -Compress -Depth 6
  $ok = $false; $err = ''
  $curl = CurlExe
  if ($curl) {
    $tmp = Join-Path $env:TEMP 'dudelock-lobby.json'
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    $code = & $curl.Source -s -m 20 -X PUT "https://api.jsonbin.io/v3/b/$BIN" -H 'Content-Type: application/json' -H "X-Master-Key: $KEY" --data-binary "@$tmp" -o NUL -w '%{http_code}' 2>$null
    if ("$code" -eq '200') { $ok = $true } else { $err = "curl http $code" }
  }
  if (-not $ok) {
    try {
      Invoke-RestMethod -UseBasicParsing -Method Put -Uri "https://api.jsonbin.io/v3/b/$BIN" -ContentType 'application/json' -Headers @{ 'X-Master-Key'=$KEY } -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
      $ok = $true
    } catch { $err = ($err + ' / ' + $_.Exception.Message).Trim(' /') }
  }
  $S.lastPub = Get-Date
  if ($ok) {
    $S.dirty = $false
    Write-Host ("  published as '{0}': {1} | {2} | me={3} | {4} heroes{5}" -f (WhoKey), $S.phase, $S.map, $S.myHero, $p.heroes.Count, $(if ($p.unknown.Count) { " | {0} unknown tokens" -f $p.unknown.Count } else { '' })) -ForegroundColor Yellow
  } else {
    Write-Host ("  publish failed: {0}" -f $err) -ForegroundColor Red
  }
}

$rxMap    = [regex]'\[Client\] Map:\s+"([^"]+)"'
$rxState  = [regex]'ChangeGameState:\s+(\w+)\s+\((\d+)\)'
$rxLobbyC = [regex]'Lobby\s+(\d+)\s+for\s+Match\s+(\d+)\s+created'
$rxLobbyD = [regex]'Lobby\s+\d+\s+for\s+Match\s+\d+\s+destroyed'
$rxPlayers= [regex]'\[Client\] Players:\s+(\d+)\s+\((\d+) bots\)'
$rxMyHero = [regex]'VMDL Camera Pose Success!.*models/heroes(?:_wip|_staging)?/([a-z0-9_]+)/'
$rxHeroTok= [regex]'(?i)hero_([a-z0-9_]+)'
$rxModel  = [regex]'(?i)models/heroes(?:_wip|_staging)?/([a-z0-9_]+)/'
$rxLoaded = [regex]'Loaded hero \d+/hero_([a-z0-9_]+)'
$rxBot    = [regex]'Created bot \d+/hero_([a-z0-9_]+)'
$rxWho    = [regex]'"([^"<]+)<\d+><\[U:1:\d+\]>'
$rxDebug  = [regex]'(?i)hero|heroes/|lobby|match|players:|team|lane|ChangeGameState|Precaching|\[U:1:|CMsgGC|slot'
$rxNoise  = [regex]'NetworkCodeGen|Creating Bone Masks|Different skeleton|Failed loading resource|hero_builds'

# epoch ms of a log line's own "MM/DD HH:MM:SS" stamp (gaming PC local time), so state recovered
# from the log tail is dated correctly; falls back to now for lines without a stamp
function LineEpoch([string]$line) {
  $m = [regex]::Match($line, '^(\d{2})/(\d{2}) (\d{2}):(\d{2}):(\d{2})')
  if ($m.Success) {
    try {
      $now = Get-Date
      $dt = Get-Date -Year $now.Year -Month ([int]$m.Groups[1].Value) -Day ([int]$m.Groups[2].Value) -Hour ([int]$m.Groups[3].Value) -Minute ([int]$m.Groups[4].Value) -Second ([int]$m.Groups[5].Value) -Millisecond 0
      if ($dt -gt $now.AddDays(1)) { $dt = $dt.AddYears(-1) }   # a December line read in January
      return [int64]($dt.ToUniversalTime() - [DateTime]'1970-01-01').TotalMilliseconds
    } catch {}
  }
  return [int64]((Get-Date).ToUniversalTime() - [DateTime]'1970-01-01').TotalMilliseconds
}
function ProcessLine([string]$line) {
  if (-not $line) { return }
  $m = $rxMap.Match($line)
  if ($m.Success) {
    $map = $m.Groups[1].Value.ToLower()
    if ($map -eq '<empty>') { return }
    if ($HIDEOUT -contains $map) { EndMatch 'back to hideout'; $S.map = $map; $S.phase = 'hideout'; $S.dirty = $true; return }
    $S.map = $map; StartMatch ("map " + $map); return
  }
  $m = $rxLobbyC.Match($line)
  if ($m.Success) { StartMatch 'lobby created'; $S.matchId = $m.Groups[2].Value; $S.dirty = $true; return }
  if ($rxLobbyD.IsMatch($line)) { EndMatch 'lobby destroyed'; return }
  $m = $rxState.Match($line)
  if ($m.Success) {
    $st = $m.Groups[1].Value
    if ($st -eq 'HeroSelection') { StartMatch 'hero selection' }
    if ($S.tracking) { $S.phase = $st; $S.dirty = $true; if ($st -eq 'GameInProgress' -and -not $S.liveAt) { $S.liveAt = LineEpoch $line } }
  }
  if ($line -match 'Disconnecting from server' -and $line -notmatch 'LOOPDEACTIVATE') { EndMatch 'disconnected'; return }
  if ($line -match 'LoopMode:\s*menu') { EndMatch 'menu'; return }
  $m = $rxPlayers.Match($line)
  if ($m.Success) { $S.players = [int]$m.Groups[1].Value; $S.dirty = $true }
  $m = $rxWho.Match($line)
  if ($m.Success -and -not $S.whoLocked) { $S.who = $m.Groups[1].Value; $S.whoLocked = $true }

  if (-not $S.tracking) { return }

  $m = $rxMyHero.Match($line)
  if ($m.Success) { $k = Norm $m.Groups[1].Value; if ($HERO.ContainsKey($k)) { if ($S.myHero -ne $HERO[$k]) { $S.myHero = $HERO[$k]; $S.dirty = $true; Write-Host ("    ME = {0}" -f $S.myHero) -ForegroundColor Magenta }; AddHero $k } }
  foreach ($mm in $rxLoaded.Matches($line)) { AddHero $mm.Groups[1].Value }
  foreach ($mm in $rxBot.Matches($line))    { AddHero $mm.Groups[1].Value }
  foreach ($mm in $rxHeroTok.Matches($line)){ AddHero $mm.Groups[1].Value }
  foreach ($mm in $rxModel.Matches($line))  { AddHero $mm.Groups[1].Value }

  # debug capture: the first few hundred relevant, non-noise lines of the match
  if ($S.debugLines -lt 600 -and $rxDebug.IsMatch($line) -and -not $rxNoise.IsMatch($line)) {
    try { Add-Content -Path $DebugFile -Value $line -Encoding UTF8; $S.debugLines++ } catch {}
  }
}

function FindLog {
  if ($LogPath -and (Test-Path $LogPath)) { return (Get-Item $LogPath) }
  $libs = @('C:\Program Files (x86)\Steam')
  $vdf = 'C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf'
  if (Test-Path $vdf) { Get-Content $vdf | Select-String '"path"' | ForEach-Object { $libs += ($_ -replace '.*"path"\s*"([^"]+)".*','$1') -replace '\\\\','\' } }
  foreach ($l in ($libs | Select-Object -Unique)) {
    $c = Join-Path $l 'steamapps\common\Deadlock\game\citadel\console.log'
    if (Test-Path $c) { return (Get-Item $c) }
    $d = Join-Path $l 'steamapps\common\Deadlock'
    if (Test-Path $d) { $f = Get-ChildItem -Path $d -Recurse -Filter 'console.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($f) { return $f } }
  }
  return $null
}

Write-Host ''
Write-Host '  DUDELOCK LOBBY WATCHER' -ForegroundColor Cyan
Write-Host '  ----------------------' -ForegroundColor DarkCyan

# ---- replay mode: run a whole saved log through the parser and show what we would publish ----
if ($Replay) {
  if (-not (Test-Path $Replay)) { Write-Host "  file not found: $Replay" -ForegroundColor Red; exit 1 }
  Write-Host "  replaying $Replay"
  $S.whoLocked = $false
  foreach ($line in [IO.File]::ReadLines($Replay)) { ProcessLine $line }
  Write-Host ''
  Write-Host ("  phase={0} map={1} match={2} players={3}" -f $S.phase, $S.map, $S.matchId, $S.players)
  Write-Host ("  me={0}" -f $S.myHero)
  Write-Host ("  heroes ({0}): {1}" -f $S.heroes.Count, (@($S.heroes.Values) -join ', '))
  if ($S.unknown.Count) { Write-Host ("  unknown tokens: {0}" -f ((@($S.unknown.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 | ForEach-Object { "{0}x{1}" -f $_.Key, $_.Value })) -join ', ')) -ForegroundColor DarkYellow }
  Write-Host ''
  Write-Host (Payload | ConvertTo-Json -Compress -Depth 4)
  if ($Publish) { PublishNow }
  exit 0
}

# ---- live mode ----
$log = FindLog
if (-not $log) {
  Write-Host '  console.log not found. Is -condebug in Deadlock''s launch options? Has the game been started since?' -ForegroundColor Red
  Write-Host '  You can also pass the path:  -LogPath "D:\SteamLibrary\steamapps\common\Deadlock\game\citadel\console.log"'
  exit 1
}
Write-Host ("  log: {0}" -f $log.FullName) -ForegroundColor Green
Write-Host ("  publishing: {0}" -f $(if ($NoPublish) { 'OFF (-NoPublish)' } else { 'ON -> shared lobby bin' }))
Write-Host '  waiting for a match... leave this window open. Ctrl+C to quit.' -ForegroundColor DarkGray

# warm up on the tail of the existing log so joining mid-match still works
$fs = New-Object IO.FileStream($log.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$len = $fs.Length
$warm = [Math]::Min($len, 600KB)
$fs.Seek($len - $warm, [IO.SeekOrigin]::Begin) | Out-Null
$buf = New-Object byte[] $warm
$n = $fs.Read($buf, 0, $warm)
$text = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
$S.whoLocked = $false
$lines = $text -split "`r?`n"
for ($i = 1; $i -lt $lines.Count; $i++) { ProcessLine $lines[$i] }   # skip the possibly-partial first line
$pos = $fs.Length
if ($S.tracking) { Write-Host '  (already in a match - state recovered from the log tail)' -ForegroundColor DarkGray }
$S.dirty = $S.tracking
$carry = ''
while ($true) {
  Start-Sleep -Milliseconds 500
  try {
    $cur = (Get-Item $log.FullName).Length
    if ($cur -lt $pos) { $pos = 0; $carry = ''; Write-Host '  log was truncated - restarting from the top' -ForegroundColor DarkGray }
    if ($cur -gt $pos) {
      $fs.Seek($pos, [IO.SeekOrigin]::Begin) | Out-Null
      $chunk = New-Object byte[] ($cur - $pos)
      $n = $fs.Read($chunk, 0, $chunk.Length)
      $pos += $n
      $text = $carry + [Text.Encoding]::UTF8.GetString($chunk, 0, $n)
      $parts = $text -split "`r?`n"
      $carry = $parts[-1]
      for ($i = 0; $i -lt $parts.Count - 1; $i++) { ProcessLine $parts[$i] }
    }
  } catch { Write-Host ("  read error: {0}" -f $_.Exception.Message) -ForegroundColor Red }
  # heartbeat: while in a match, refresh our slot every 60 s so the site never thinks it went stale
  if ($S.tracking -and -not $NoPublish -and ((Get-Date) - $S.lastPub).TotalSeconds -ge 60) { $S.dirty = $true }
  if ($S.dirty -and -not $NoPublish -and ((Get-Date) - $S.lastPub).TotalSeconds -ge $(if ($S.dirty -and $S.lastPub -gt [DateTime]::MinValue) { 5 } else { 2 })) { PublishNow }
}
