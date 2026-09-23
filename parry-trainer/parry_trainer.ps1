# DUDELOCK PARRY TRAINER
# ======================
# Plays Deadlock's heavy-melee cue at random intervals and grades how fast you
# parry - with an instant good/bad sound so you never have to look at this
# window while you play.
#
# Runs on any Windows machine: no installs, no admin, no Python. It has to be a
# local script rather than a page on the site because a browser cannot read your
# keyboard while Deadlock has focus. Windows can, through GetAsyncKeyState.

Add-Type -Name Keys -Namespace Dudelock -MemberDefinition @'
[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
[DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint uMilliseconds);
[DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint uMilliseconds);
'@

$root       = $PSScriptRoot
$configPath = Join-Path $root 'parry_config.json'
$heavyPath  = Join-Path $root 'heavy_melee.wav'
$goodPath   = Join-Path $root 'good.wav'
$badPath    = Join-Path $root 'bad.wav'

# ---------------------------------------------------------------- key names --
$VkNames = @{
  1='Left Mouse'; 2='Right Mouse'; 4='Middle Mouse'; 5='Mouse 4'; 6='Mouse 5'
  8='Backspace'; 9='Tab'; 13='Enter'; 16='Shift'; 17='Ctrl'; 18='Alt'
  20='Caps Lock'; 32='Space'; 45='Insert'; 46='Delete'
  37='Left Arrow'; 38='Up Arrow'; 39='Right Arrow'; 40='Down Arrow'
  160='Left Shift'; 161='Right Shift'; 162='Left Ctrl'; 163='Right Ctrl'
  164='Left Alt'; 165='Right Alt'
  186=';'; 187='='; 188=','; 189='-'; 190='.'; 191='/'; 192='`'
  219='['; 220='\'; 221=']'; 222="'"
}
48..57  | ForEach-Object { $VkNames[$_] = [char]$_ }
65..90  | ForEach-Object { $VkNames[$_] = [char]$_ }
1..12   | ForEach-Object { $VkNames[111 + $_] = "F$_" }

function Get-VkName([int]$vk) {
  if ($VkNames.ContainsKey($vk)) { return [string]$VkNames[$vk] }
  return ('key 0x{0:X2}' -f $vk)
}

function Test-KeyDown([int]$vk) {
  return ([Dudelock.Keys]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
}

function New-Player([string]$path) {
  if (-not (Test-Path $path)) { return $null }
  $p = New-Object System.Media.SoundPlayer
  $p.SoundLocation = $path
  try { $p.Load(); return $p } catch { return $null }
}

# ------------------------------------------------------------------- config --
function Get-Config {
  $cfg = [ordered]@{
    parry_vk = 0; parry_label = ''; min_delay = 5.0; max_delay = 30.0
    window = 600; feedback = $true
  }
  if (Test-Path $configPath) {
    try {
      $saved = Get-Content $configPath -Raw | ConvertFrom-Json
      foreach ($k in @($cfg.Keys)) {
        if ($null -ne $saved.$k) { $cfg[$k] = $saved.$k }
      }
    } catch { }
  }
  return $cfg
}

function Save-Config($cfg) {
  try { ($cfg | ConvertTo-Json) | Set-Content $configPath -Encoding utf8 } catch { }
}

function Get-HeldKeys {
  $held = @()
  foreach ($vk in 1..254) { if (Test-KeyDown $vk) { $held += $vk } }
  return $held
}

function Read-ParryKey {
  Write-Host ''
  Write-Host '  Press the key you use to PARRY in Deadlock (Esc cancels)...' -ForegroundColor Yellow
  # Some machines report a key as permanently held (stuck modifier, mouse/keyboard
  # vendor software, Steam Input, remote desktop). The old version waited for ALL
  # keys to be up before listening and hung forever on those. Now we snapshot
  # what's down at the prompt and only accept a key that goes UP -> DOWN after it.
  $base = @{}
  foreach ($vk in 1..254) { $base[$vk] = Test-KeyDown $vk }
  $stuck = @($base.Keys | Where-Object { $base[$_] })
  if ($stuck.Count -gt 0) {
    Write-Host ('  (ignoring keys Windows says are already held: ' + (($stuck | Sort-Object | ForEach-Object { Get-VkName $_ }) -join ', ') + ')') -ForegroundColor DarkGray
  }
  while ($true) {
    if ((Test-KeyDown 27) -and -not $base[27]) { return 0 }
    foreach ($vk in 1..254) {
      if ($vk -eq 27) { continue }
      $down = Test-KeyDown $vk
      if ($down -and -not $base[$vk]) {
        while (Test-KeyDown $vk) { [System.Threading.Thread]::Sleep(10) }
        return $vk
      }
      if (-not $down) { $base[$vk] = $false }   # released since the prompt -> a fresh press now counts
    }
    [System.Threading.Thread]::Sleep(2)
  }
}

# ------------------------------------------------------------------ session --
function Start-Session($cfg) {
  $vk       = [int]$cfg.parry_vk
  $label    = [string]$cfg.parry_label
  if ([string]::IsNullOrEmpty($label)) { $label = Get-VkName $vk }
  $windowMs = [double]$cfg.window
  $lo       = [double]$cfg.min_delay
  $hi       = [double]$cfg.max_delay
  $useFb    = [bool]$cfg.feedback

  $heavy = New-Player $heavyPath
  if ($null -eq $heavy) { Write-Host '  Could not load heavy_melee.wav' -ForegroundColor Red; return }
  $good = $null; $bad = $null
  if ($useFb) { $good = New-Player $goodPath; $bad = New-Player $badPath }

  $fbLine = 'off'
  if ($useFb -and $good -and $bad) { $fbLine = 'on - chime = parried, buzz = missed' }

  Write-Host ''
  Write-Host ('  ' + ('=' * 60)) -ForegroundColor DarkYellow
  Write-Host '   TRAINING - alt-tab into Deadlock now, this keeps listening.' -ForegroundColor Yellow
  Write-Host ("   Parry key : $label")
  Write-Host ('   Cue every : {0:N0} - {1:N0} s   |   window: {2:N0} ms' -f $lo, $hi, $windowMs)
  Write-Host ("   Feedback  : $fbLine")
  Write-Host '   Quit      : hold Esc'
  Write-Host ('  ' + ('=' * 60)) -ForegroundColor DarkYellow
  Write-Host ''

  # 1 ms timer resolution, otherwise Windows rounds to ~15 ms and smears every
  # reaction time we report
  [void][Dudelock.Keys]::timeBeginPeriod(1)

  $rng   = New-Object System.Random
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $hits = 0; $misses = 0; $early = 0
  $times = New-Object System.Collections.ArrayList

  $nextCue = $watch.Elapsed.TotalMilliseconds + ($rng.NextDouble() * 3000 + 2000)
  $armedAt = -1.0
  $wasDown = Test-KeyDown $vk
  $rep     = 0

  while ($true) {
    $now = $watch.Elapsed.TotalMilliseconds
    if (Test-KeyDown 27) { break }

    $down    = Test-KeyDown $vk
    $pressed = $down -and (-not $wasDown)
    $wasDown = $down

    if ($armedAt -ge 0) {
      $elapsed = $now - $armedAt
      if ($pressed) {
        $hits++
        [void]$times.Add($elapsed)
        if ($good) { $good.Play() }
        Write-Host ('  [{0:D2}] PARRIED  - {1:N0} ms' -f $rep, $elapsed) -ForegroundColor Green
        $armedAt = -1.0
        $nextCue = $now + ($rng.NextDouble() * ($hi - $lo) + $lo) * 1000
        continue
      }
      if ($elapsed -ge $windowMs) {
        $misses++
        if ($bad) { $bad.Play() }
        Write-Host ('  [{0:D2}] MISSED   - no parry inside {1:N0} ms' -f $rep, $windowMs) -ForegroundColor Red
        $armedAt = -1.0
        $nextCue = $now + ($rng.NextDouble() * ($hi - $lo) + $lo) * 1000
        continue
      }
    }
    elseif ($pressed) {
      $early++
      if ($bad) { $bad.Play() }
      Write-Host ('       early    - parried at nothing ({0} total)' -f $early) -ForegroundColor DarkYellow
    }

    if ($armedAt -lt 0 -and $now -ge $nextCue) {
      $rep++
      $armedAt = $watch.Elapsed.TotalMilliseconds
      $heavy.Play()
    }

    [System.Threading.Thread]::Sleep(1)
  }

  [void][Dudelock.Keys]::timeEndPeriod(1)

  Write-Host ''
  Write-Host ('  ' + ('=' * 60)) -ForegroundColor DarkYellow
  Write-Host '   SESSION OVER' -ForegroundColor Yellow
  $real = $hits + $misses
  if ($real -gt 0) {
    Write-Host ('   Parried  : {0} / {1}  ({2:N0}%)' -f $hits, $real, (100.0 * $hits / $real))
  }
  if ($times.Count -gt 0) {
    $sorted = $times | Sort-Object
    $best   = $sorted[0]
    $median = $sorted[[int]([math]::Floor($sorted.Count / 2))]
    $avg    = ($times | Measure-Object -Average).Average
    Write-Host ('   Reaction : best {0:N0} ms | median {1:N0} ms | avg {2:N0} ms' -f $best, $median, $avg)
    if ($avg -lt 250) {
      Write-Host '              that is genuinely fast - tighten the window and go again' -ForegroundColor Green
    } elseif ($avg -lt 400) {
      Write-Host '              solid - drop the window toward 400 ms to push it' -ForegroundColor Green
    }
  }
  if ($early -gt 0) {
    Write-Host ('   Early    : {0}  (parried with no cue at all)' -f $early) -ForegroundColor DarkYellow
  }
  if ($real -eq 0 -and $early -eq 0) { Write-Host '   No reps logged.' }
  Write-Host ('  ' + ('=' * 60)) -ForegroundColor DarkYellow
  Write-Host ''
}

# --------------------------------------------------------------------- main --
Write-Host ''
Write-Host '   D U D E L O C K   -   P A R R Y   T R A I N E R' -ForegroundColor Yellow
Write-Host '   ----------------------------------------------' -ForegroundColor DarkYellow

if (-not (Test-Path $heavyPath)) {
  Write-Host ''
  Write-Host '  Missing heavy_melee.wav next to this script.' -ForegroundColor Red
  Read-Host '  Press Enter to close'
  exit
}

$cfg = Get-Config

if ([int]$cfg.parry_vk -eq 0) {
  $vk = Read-ParryKey
  if ($vk -eq 0) { Write-Host '  Cancelled.'; exit }
  $cfg.parry_vk    = $vk
  $cfg.parry_label = Get-VkName $vk
  Save-Config $cfg
  Write-Host ('  Parry key set to: ' + $cfg.parry_label) -ForegroundColor Green
}

while ($true) {
  $lbl = [string]$cfg.parry_label
  if ([string]::IsNullOrEmpty($lbl)) { $lbl = Get-VkName ([int]$cfg.parry_vk) }
  $fbState = 'off'
  if ([bool]$cfg.feedback) { $fbState = 'on' }

  Write-Host ''
  Write-Host ("  Parry key : $lbl")
  Write-Host ('  Interval  : {0:N0} - {1:N0} seconds' -f [double]$cfg.min_delay, [double]$cfg.max_delay)
  Write-Host ('  Window    : {0:N0} ms' -f [double]$cfg.window)
  Write-Host ("  Feedback  : $fbState")
  Write-Host ''
  Write-Host '  [Enter] start    [k] change key    [s] settings    [d] key diagnostic    [q] quit' -ForegroundColor DarkYellow
  $choice = (Read-Host '  >').Trim().ToLower()

  if ($choice -eq 'q') { break }
  elseif ($choice -eq 'd') {
    # for debugging "it won't take my key": shows what Windows thinks is held, live
    Write-Host ''
    Write-Host '  Watching key state for 8 seconds - press your parry key a few times...' -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew(); $last = ''
    while ($sw.Elapsed.TotalSeconds -lt 8) {
      $now = ((Get-HeldKeys | ForEach-Object { Get-VkName $_ }) -join ', ')
      if ($now -ne $last) { Write-Host ('    ' + $sw.Elapsed.ToString('s\.ff') + 's  held: ' + $(if ($now) { $now } else { '(nothing)' })); $last = $now }
      [System.Threading.Thread]::Sleep(15)
    }
    Write-Host '  If a key shows as held the whole time without you touching it, that is the culprit.' -ForegroundColor DarkGray
  }
  elseif ($choice -eq 'k') {
    $vk = Read-ParryKey
    if ($vk -ne 0) {
      $cfg.parry_vk    = $vk
      $cfg.parry_label = Get-VkName $vk
      Save-Config $cfg
      Write-Host ('  Parry key set to: ' + $cfg.parry_label) -ForegroundColor Green
    }
  }
  elseif ($choice -eq 's') {
    $v = Read-Host ('  shortest gap between cues, seconds [{0:N0}]' -f [double]$cfg.min_delay)
    if ($v) { try { $cfg.min_delay = [math]::Max(1.0, [double]$v) } catch { } }
    $v = Read-Host ('  longest gap between cues, seconds [{0:N0}]' -f [double]$cfg.max_delay)
    if ($v) { try { $cfg.max_delay = [math]::Max([double]$cfg.min_delay, [double]$v) } catch { } }
    $v = Read-Host ('  parry window, milliseconds [{0:N0}]' -f [double]$cfg.window)
    if ($v) { try { $cfg.window = [math]::Max(50.0, [double]$v) } catch { } }
    $v = Read-Host ('  good/bad feedback sounds? y/n [{0}]' -f $fbState)
    if ($v) { $cfg.feedback = $v.ToLower().StartsWith('y') }
    Save-Config $cfg
  }
  else { Start-Session $cfg }
}
