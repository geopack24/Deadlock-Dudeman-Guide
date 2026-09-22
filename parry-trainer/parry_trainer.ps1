# DUDELOCK PARRY TRAINER
# ======================
# Plays the heavy-melee cue at random intervals and grades how fast you parry.
# Runs on any Windows machine - no installs, no admin, no Python.
#
# Why this is a local script and not a page on the site: a browser cannot read
# your keyboard while Deadlock has focus. Windows can, through GetAsyncKeyState,
# which is what this polls. Start it, alt-tab into Deadlock, and it keeps
# listening while you play.

Add-Type -Name Keys -Namespace Dudelock -MemberDefinition @'
[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
[DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint uMilliseconds);
[DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint uMilliseconds);
'@

$root       = $PSScriptRoot
$configPath = Join-Path $root 'parry_config.json'
$heavyPath  = Join-Path $root 'heavy_melee.wav'
$lightPath  = Join-Path $root 'light_melee.wav'

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
48..57  | ForEach-Object { $VkNames[$_] = [char]$_ }           # 0-9
65..90  | ForEach-Object { $VkNames[$_] = [char]$_ }           # A-Z
1..12   | ForEach-Object { $VkNames[111 + $_] = "F$_" }        # F1-F12

function Get-VkName([int]$vk) {
  if ($VkNames.ContainsKey($vk)) { return [string]$VkNames[$vk] }
  return ('key 0x{0:X2}' -f $vk)
}

function Test-KeyDown([int]$vk) {
  return ([Dudelock.Keys]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
}

# ------------------------------------------------------------------- config --
function Get-Config {
  $cfg = [ordered]@{
    parry_vk = 0; parry_label = ''; min_delay = 5.0; max_delay = 30.0
    window = 600; decoys = $true; decoy_chance = 0.35
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

function Read-ParryKey {
  Write-Host ''
  Write-Host '  Press the key you use to PARRY in Deadlock (Esc cancels)...' -ForegroundColor Yellow
  # wait for a clean slate so we catch a fresh press
  $held = $true
  while ($held) {
    $held = $false
    foreach ($vk in 1..254) { if (Test-KeyDown $vk) { $held = $true; break } }
    if ($held) { [System.Threading.Thread]::Sleep(20) }
  }
  while ($true) {
    if (Test-KeyDown 27) { return 0 }
    foreach ($vk in 1..254) {
      if ($vk -eq 27) { continue }
      if (Test-KeyDown $vk) {
        while (Test-KeyDown $vk) { [System.Threading.Thread]::Sleep(10) }
        return $vk
      }
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
  $useDecoy = ([bool]$cfg.decoys) -and (Test-Path $lightPath)

  $heavy = New-Object System.Media.SoundPlayer
  $heavy.SoundLocation = $heavyPath
  try { $heavy.Load() } catch { Write-Host "  Could not load heavy_melee.wav" -ForegroundColor Red; return }
  $light = $null
  if ($useDecoy) {
    $light = New-Object System.Media.SoundPlayer
    $light.SoundLocation = $lightPath
    try { $light.Load() } catch { $useDecoy = $false }
  }

  $decoyLine = 'off'
  if ($useDecoy) { $decoyLine = 'ON - ignore the short snappy sound' }

  Write-Host ''
  Write-Host ('  ' + ('=' * 60)) -ForegroundColor DarkYellow
  Write-Host '   TRAINING - alt-tab into Deadlock now, this keeps listening.' -ForegroundColor Yellow
  Write-Host ("   Parry key : $label")
  Write-Host ('   Cue every : {0:N0} - {1:N0} s   |   window: {2:N0} ms' -f $lo, $hi, $windowMs)
  Write-Host ("   Decoys    : $decoyLine")
  Write-Host '   Quit      : hold Esc'
  Write-Host ('  ' + ('=' * 60)) -ForegroundColor DarkYellow
  Write-Host ''

  # ask Windows for 1 ms timer resolution so reaction times are honest
  # (default is ~15 ms, which would smear every measurement)
  [void][Dudelock.Keys]::timeBeginPeriod(1)

  $rng     = New-Object System.Random
  $watch   = [System.Diagnostics.Stopwatch]::StartNew()
  $hits = 0; $misses = 0; $early = 0; $baited = 0
  $times   = New-Object System.Collections.ArrayList

  # first cue lands quickly so you are not staring at a blank screen
  $nextCue = $watch.Elapsed.TotalMilliseconds + ($rng.NextDouble() * 3000 + 2000)
  $armedAt = -1.0
  $isDecoy = $false
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
        if ($isDecoy) {
          $baited++
          Write-Host ('  [{0:D2}] BAITED   - that was a light melee, hands off' -f $rep) -ForegroundColor Magenta
        } else {
          $hits++
          [void]$times.Add($elapsed)
          Write-Host ('  [{0:D2}] PARRIED  - {1:N0} ms' -f $rep, $elapsed) -ForegroundColor Green
        }
        $armedAt = -1.0
        $nextCue = $now + ($rng.NextDouble() * ($hi - $lo) + $lo) * 1000
        continue
      }
      if ($elapsed -ge $windowMs) {
        if ($isDecoy) {
          Write-Host ('  [{0:D2}] ignored  - good, that was a decoy' -f $rep) -ForegroundColor DarkGray
        } else {
          $misses++
          Write-Host ('  [{0:D2}] MISSED   - no parry inside {1:N0} ms' -f $rep, $windowMs) -ForegroundColor Red
        }
        $armedAt = -1.0
        $nextCue = $now + ($rng.NextDouble() * ($hi - $lo) + $lo) * 1000
        continue
      }
    }
    elseif ($pressed) {
      $early++
      Write-Host ('       early    - parried at nothing ({0} total)' -f $early) -ForegroundColor DarkYellow
    }

    if ($armedAt -lt 0 -and $now -ge $nextCue) {
      $rep++
      $isDecoy = $useDecoy -and ($rng.NextDouble() -lt [double]$cfg.decoy_chance)
      $armedAt = $watch.Elapsed.TotalMilliseconds
      if ($isDecoy) { $light.Play() } else { $heavy.Play() }
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
  if ($baited -gt 0) {
    Write-Host ('   Baited   : {0}  (parried a light melee - the habit that gets you killed)' -f $baited) -ForegroundColor Magenta
  }
  if ($early -gt 0) {
    Write-Host ('   Early    : {0}  (parried with no cue at all)' -f $early) -ForegroundColor DarkYellow
  }
  if ($real -eq 0 -and $early -eq 0 -and $baited -eq 0) {
    Write-Host '   No reps logged.'
  }
  Write-Host ('  ' + ('=' * 60)) -ForegroundColor DarkYellow
  Write-Host ''
}

# --------------------------------------------------------------------- main --
Write-Host ''
Write-Host '   D U D E L O C K   -   P A R R Y   T R A I N E R' -ForegroundColor Yellow
Write-Host '   ----------------------------------------------' -ForegroundColor DarkYellow

if (-not (Test-Path $heavyPath)) {
  Write-Host ''
  Write-Host "  Missing heavy_melee.wav next to this script." -ForegroundColor Red
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
  Write-Host ("  Parry key set to: " + $cfg.parry_label) -ForegroundColor Green
}

while ($true) {
  $lbl = [string]$cfg.parry_label
  if ([string]::IsNullOrEmpty($lbl)) { $lbl = Get-VkName ([int]$cfg.parry_vk) }
  $decoyState = 'off'
  if ([bool]$cfg.decoys) { $decoyState = 'on' }

  Write-Host ''
  Write-Host ("  Parry key : $lbl")
  Write-Host ('  Interval  : {0:N0} - {1:N0} seconds' -f [double]$cfg.min_delay, [double]$cfg.max_delay)
  Write-Host ('  Window    : {0:N0} ms' -f [double]$cfg.window)
  Write-Host ("  Decoys    : $decoyState")
  Write-Host ''
  Write-Host '  [Enter] start    [k] change key    [s] settings    [q] quit' -ForegroundColor DarkYellow
  $choice = (Read-Host '  >').Trim().ToLower()

  if ($choice -eq 'q') { break }
  elseif ($choice -eq 'k') {
    $vk = Read-ParryKey
    if ($vk -ne 0) {
      $cfg.parry_vk    = $vk
      $cfg.parry_label = Get-VkName $vk
      Save-Config $cfg
      Write-Host ("  Parry key set to: " + $cfg.parry_label) -ForegroundColor Green
    }
  }
  elseif ($choice -eq 's') {
    $v = Read-Host ('  shortest gap between cues, seconds [{0:N0}]' -f [double]$cfg.min_delay)
    if ($v) { try { $cfg.min_delay = [math]::Max(1.0, [double]$v) } catch { } }
    $v = Read-Host ('  longest gap between cues, seconds [{0:N0}]' -f [double]$cfg.max_delay)
    if ($v) { try { $cfg.max_delay = [math]::Max([double]$cfg.min_delay, [double]$v) } catch { } }
    $v = Read-Host ('  parry window, milliseconds [{0:N0}]' -f [double]$cfg.window)
    if ($v) { try { $cfg.window = [math]::Max(50.0, [double]$v) } catch { } }
    $v = Read-Host ('  decoy light-melee cues? y/n [{0}]' -f $decoyState)
    if ($v) { $cfg.decoys = $v.ToLower().StartsWith('y') }
    Save-Config $cfg
  }
  else { Start-Session $cfg }
}
