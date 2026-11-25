# Window helpers for the Isaac Bot scripts: find the bot's windows, remember their spots, close them.
# Two windows: "Isaac Bot helper" (dashboard, redraws in place) and "Isaac Bot log" (scrolling log).
# Dot-source this file:  . "$PSScriptRoot\win.ps1"

if (-not ("IBotWin" -as [type])) {
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class IBotWin {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int ht, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> FindByTitle(string title) {
    var found = new List<IntPtr>();
    EnumWindows((h, p) => {
      if (IsWindowVisible(h)) {
        var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
        if (sb.ToString().StartsWith(title)) found.Add(h);
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@
}

# title -> (file with its saved spot, process command-line pattern, default spot if none saved yet)
$IBotWindows = @(
    @{ title = "Isaac Bot helper"; file = (Join-Path $PSScriptRoot "helper_window.json"); proc = "*isaac-bot*helper*";
       default = $null },
    @{ title = "Isaac Bot log";    file = (Join-Path $PSScriptRoot "log_window.json");    proc = "*isaac-bot*logview*";
       default = $null }   # no saved spot yet: Windows places it; its spot is remembered from then on
)
$IBotHelperTitle = "Isaac Bot helper"

function Save-BotWindows {
    # Remember where the user put each bot window (not while maximised).
    foreach ($win in $IBotWindows) {
        foreach ($h in [IBotWin]::FindByTitle($win.title)) {
            if ([IBotWin]::IsZoomed($h)) { continue }
            $r = New-Object IBotWin+RECT
            [void][IBotWin]::GetWindowRect($h, [ref]$r)
            @{ x = $r.L; y = $r.T; w = $r.R - $r.L; h = $r.B - $r.T; saved = (Get-Date -Format s) } |
                ConvertTo-Json | Set-Content -Path $win.file -Encoding utf8
            break
        }
    }
}

function Close-BotWindows {
    # Closes every bot window and the processes behind them, so there's never a duplicate.
    foreach ($win in $IBotWindows) {
        Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like $win.proc } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Milliseconds 400
    foreach ($win in $IBotWindows) {
        foreach ($h in [IBotWin]::FindByTitle($win.title)) {
            [void][IBotWin]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_CLOSE
        }
    }
}

function Place-BotWindow([string]$title, [int]$timeoutSec = 10) {
    # Moves a freshly opened bot window to its saved spot (or its default) once it appears.
    $win = $IBotWindows | Where-Object { $_.title -eq $title } | Select-Object -First 1
    $spot = $null
    if (Test-Path $win.file) { $spot = Get-Content $win.file -Raw | ConvertFrom-Json } elseif ($win.default) { $spot = [pscustomobject]$win.default }
    if (-not $spot) { return $false }
    $end = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $end) {
        $h = [IBotWin]::FindByTitle($title) | Select-Object -First 1
        if ($h) {
            [void][IBotWin]::ShowWindow($h, 9)  # SW_RESTORE (in case it opened maximised)
            [void][IBotWin]::SetWindowPos($h, [IntPtr]::Zero, $spot.x, $spot.y, $spot.w, $spot.h, 0x0004)  # SWP_NOZORDER
            return $true
        }
        Start-Sleep -Milliseconds 250
    }
    return $false
}
