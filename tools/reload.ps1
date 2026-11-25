# Safe reload: compile-check every Lua file offline (luacheck.ps1, Isaac's own Lua engine), then reload the bot's
# code in the running game, wait for its "start" line, and scan the game's log for Lua errors.
#   powershell -ExecutionPolicy Bypass -File tools\reload.ps1
$root = Split-Path -Parent $PSScriptRoot
$check = & C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'luacheck.ps1')
$check
if ($LASTEXITCODE -ne 0) { Write-Output "NOT reloaded: fix the errors above first"; exit 1 }
# offline logic tests (test\run.ps1): today's bugs as scripted situations; a FAIL blocks the reload unless -Force
$tests = & C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test\run.ps1')
$testsFailed = $LASTEXITCODE -ne 0
$tests | Where-Object { $_ -match '^(FAIL|CRASH|ERROR)|passed' }
if ($testsFailed -and -not ($args -contains '-Force')) { Write-Output "NOT reloaded: a logic test failed (add -Force to reload anyway)"; exit 1 }

. (Join-Path $PSScriptRoot 'config.ps1')
$runs = Join-Path (Get-BotConfig).bot_dir 'runs'   # bot_dir from config.json (default: this repo)
$live = Join-Path $runs 'live.log'
$gameLog = Join-Path $env:USERPROFILE 'Documents\My Games\Binding of Isaac Repentance+\log.txt'
$before = (Get-Content $live).Count
$gameBefore = (Get-Content $gameLog).Count
[IO.File]::WriteAllBytes((Join-Path $runs 'send.txt'), [Text.Encoding]::UTF8.GetBytes("reload`n"))
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    $new = Get-Content $live | Select-Object -Skip $before
    $start = $new | Where-Object { $_ -match ' start  .*\|reload\|' } | Select-Object -Last 1
    if ($start) { Write-Output $start; $ok = $true; break }
}
$errs = Get-Content $gameLog | Select-Object -Skip $gameBefore | Where-Object { $_ -match 'isaac-bot/.*\.lua:\d+|error running' }
if ($errs) { Write-Output "LUA ERRORS in the game:"; $errs | Select-Object -First 5 }
if (-not $ok) { Write-Output "no 'start' line within 10 s: the mod may have failed to load (see above)"; exit 1 }
