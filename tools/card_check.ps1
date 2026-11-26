# Card check: every enemy card's body forecast against the recordings (test\card_check.lua). Builds cards.lua first.
#   powershell -ExecutionPolicy Bypass -File tools\card_check.ps1
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'config.ps1')
$py = (Get-BotConfig).python
& $py (Join-Path $PSScriptRoot 'build_cards.py')
if ($LASTEXITCODE -ne 0) { exit 1 }
$list = Join-Path $root 'runs\recorder\rec_files.txt'
New-Item -ItemType Directory -Force (Split-Path $list) | Out-Null
(Get-ChildItem (Join-Path $root 'runs\logs\live-*.log') | Sort-Object Name | ForEach-Object { $_.FullName.Replace('\', '/') }) |
  Set-Content -Path $list -Encoding ascii
& C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test\run.ps1') -Tests (Join-Path $root 'test\card_check.lua')
