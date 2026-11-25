# One-click start for the Isaac Bot.
#  1. remembers where the helper window is, closes it (never two open), and opens a fresh one in the same spot
#  2. starts Isaac through the REPENTOGON launcher with no clicks: the launcher's "StealthMode" is switched
#     on just for this launch and switched back to the user's setting once the game is up
#  -Restart also closes a running game first (used after mod changes).
# The mod then loads save slot 2 and starts a run as Isaac by itself.
param([switch]$Restart)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\win.ps1"
. "$PSScriptRoot\config.ps1"
$cfg      = Get-BotConfig      # paths come from config.json (see config.example.json)
$root     = Split-Path -Parent $PSScriptRoot
$launcher = $cfg.repentogon_launcher
$ini      = $cfg.repentogon_ini

function Set-Stealth([string]$value) {
    if (-not (Test-Path $ini)) { return }   # no launcher settings file: just start the launcher as it is
    $text = [IO.File]::ReadAllText($ini)
    $new  = [regex]::Replace($text, "(?m)^StealthMode\s*=\s*\d+", "StealthMode = $value")
    if ($new -ne $text) { [IO.File]::WriteAllText($ini, $new) }
}

Write-Host "Isaac Bot: starting..." -ForegroundColor Red

# 1. bot windows: remember their spots, close the old ones (never two of the same)
Save-BotWindows
Close-BotWindows

# 2. restart: close the game too
$game = Get-Process isaac-ng -ErrorAction SilentlyContinue
if ($Restart -and $game) {
    Write-Host "Closing Isaac..."
    [void]$game.CloseMainWindow()
    $end = (Get-Date).AddSeconds(6)
    while ((Get-Process isaac-ng -ErrorAction SilentlyContinue) -and (Get-Date) -lt $end) { Start-Sleep -Milliseconds 300 }
    if (Get-Process isaac-ng -ErrorAction SilentlyContinue) { Stop-Process -Name isaac-ng -Force }
    Start-Sleep -Seconds 3   # let the game finish writing its files before the next launch (a fast relaunch crashed once)
    $game = $null
}

# 3. fresh windows in their saved spots (Windows Terminal; plain cmd if that's missing):
#    "Isaac Bot helper" = dashboard (redraws in place), "Isaac Bot log" = everything scrolling
$wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
# cmd keeps the quotes when there are exactly two of them around the path, so no nested quotes here.
$windows = @(
    @{ title = "Isaac Bot helper"; cmd = "cmd /k `"$root\helper.cmd`" --auto" },
    @{ title = "Isaac Bot log";    cmd = "cmd /k `"$root\logview.cmd`"" }
)
foreach ($w in $windows) {
    if ($wt) { Start-Process $wt -ArgumentList "-w new --title `"$($w.title)`" $($w.cmd)" }
    else     { Start-Process cmd.exe -ArgumentList ($w.cmd -replace '^cmd ', '') }
    if (Place-BotWindow $w.title) { Write-Host "$($w.title) window opened in its spot." } else { Write-Host "$($w.title) window opened." }
}

# 3b. the brain needs Ollama (started via Explorer so it outlives this script)
if (-not (Get-Process ollama -ErrorAction SilentlyContinue)) {
    $ollama = "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe"
    if (Test-Path $ollama) { Start-Process explorer.exe -ArgumentList "`"$ollama`""; Write-Host "Started Ollama for the brain." }
}

# 4. the game
if ($game) {
    Write-Host "Isaac is already running. The bot takes over the menu whenever the game is on it."
    exit 0
}
if (-not $launcher -or -not (Test-Path $launcher)) {
    Write-Host "REPENTOGON launcher not found ('$launcher'). Set repentogon_launcher in config.json." -ForegroundColor Yellow
    exit 1
}

# The launcher stays alive (hidden) after the game closes, and a second copy refuses to start
# ("already launching"). With no game running, that old copy is idle, so close it first.
$old = Get-Process REPENTOGONLauncher -ErrorAction SilentlyContinue
if ($old) { $old | Stop-Process -Force; Start-Sleep -Seconds 2 }

$original = "0"
if (Test-Path $ini) {
    $m = Select-String -Path $ini -Pattern "^StealthMode\s*=\s*(\d+)"
    if ($m) { $original = $m.Matches[0].Groups[1].Value }
}
if ($original -eq "1") { $original = "0" }  # a cut-off earlier start may have left it on; the usual setting is 0
try {
    Set-Stealth "1"
    Start-Process $launcher -WorkingDirectory (Split-Path $launcher)
    Write-Host "Launcher started, waiting for the game..."
    $deadline = (Get-Date).AddMinutes(3)
    while (-not (Get-Process isaac-ng -ErrorAction SilentlyContinue)) {
        if ((Get-Date) -gt $deadline) { Write-Host "The game didn't start within 3 minutes. Check the launcher window." -ForegroundColor Yellow; break }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 5   # give the launcher time to finish reading its settings
}
finally {
    Set-Stealth $original
}
Write-Host "Game is up. Launcher setting restored (StealthMode = $original)."
