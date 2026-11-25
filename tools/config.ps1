# Local settings for the Isaac Bot scripts (same file and defaults as brain\botconfig.py).
# Copy config.example.json (repo root) to config.json and fill it in; config.json is never committed.
#   Dot-source:  . "$PSScriptRoot\config.ps1"; $cfg = Get-BotConfig
#   One value:   powershell -File tools\config.ps1 -Get python     (used by helper.cmd / logview.cmd)
param([string]$Get = '')

function Get-BotConfig {
    $repo = Split-Path -Parent $PSScriptRoot
    $cfg = @{
        game_dir            = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth'
        steam_userdata      = ''
        ffmpeg              = 'ffmpeg'
        python              = 'python'
        repentogon_launcher = ''
        repentogon_ini      = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\repentogon_launcher.ini')
        bot_dir             = $repo
    }
    $file = Join-Path $repo 'config.json'
    if (Test-Path $file) {
        $json = Get-Content $file -Raw | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) {
            if (-not $p.Name.StartsWith('_') -and $null -ne $p.Value -and "$($p.Value)" -ne '') { $cfg[$p.Name] = "$($p.Value)" }
        }
    }
    return $cfg
}

if ($Get) { (Get-BotConfig)[$Get] }
