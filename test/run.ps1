# Offline logic tests: runs test\tests.lua (scenarios) against the bot's REAL Lua code with a fake Isaac
# (test\mock.lua), inside Isaac's own Lua engine. No game needed; takes a few seconds.
# The DLL is 32-bit, so this runs in 32-bit PowerShell:
#   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File test\run.ps1
# Options:
#   -Only "text"   run only the tests whose name contains this text
#   -Prove         for every entry in test\mutants.lua: undo one fix IN MEMORY (the mod files are never touched),
#                  run the test that guards it, and check it FAILS. "NOT CAUGHT" = that test no longer guards
#                  its fix; "STALE" = the code changed and the patch no longer matches (update mutants.lua).
# Pattern from an earlier Isaac mod's offline test runner.
param([string]$Game = '', [string]$Only = '',   # -Game default: game_dir from config.json
      [switch]$Prove, [string]$Tests = '')

$root = Split-Path -Parent $PSScriptRoot
if (-not $Game) { . (Join-Path $root 'tools\config.ps1'); $Game = (Get-BotConfig).game_dir }
$dll = (Join-Path $Game 'Lua5.3.3r.dll').Replace('\', '\\')

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class LuaRun {
    const string D = "$dll";
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr luaL_newstate();
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern void luaL_openlibs(IntPtr L);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern void lua_close(IntPtr L);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern int luaL_loadstring(IntPtr L, string s);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern int lua_pcallk(IntPtr L, int n, int r, int e, IntPtr ctx, IntPtr k);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr lua_tolstring(IntPtr L, int i, IntPtr len);
    public static string Run(string chunk) {
        IntPtr L = luaL_newstate();
        luaL_openlibs(L);
        int rc = luaL_loadstring(L, chunk);
        if (rc == 0) rc = lua_pcallk(L, 0, 1, 0, IntPtr.Zero, IntPtr.Zero);
        string s = Marshal.PtrToStringAnsi(lua_tolstring(L, -1, IntPtr.Zero));
        lua_close(L);
        return (rc == 0 ? "" : "ERROR ") + s;
    }
}
"@

function LuaPath($p) { $p.Replace('\', '/') }
$mod = LuaPath (Join-Path $root 'mod\isaac-bot')
$mock = LuaPath (Join-Path $PSScriptRoot 'mock.lua')
$tests = LuaPath $(if ($Tests) { (Resolve-Path $Tests).Path } else { Join-Path $PSScriptRoot 'tests.lua' })
$mutants = LuaPath (Join-Path $PSScriptRoot 'mutants.lua')

# one fresh Lua state per run; $pre = Lua lines run first (ONLY / MUTANT)
function Invoke-Tests([string]$pre) {
    $chunk = @"
MOD_DIR = '$mod'
$pre
local ok, res = xpcall(function() dofile('$mock'); return dofile('$tests') end, debug.traceback)
local tail = MUTANT and ('\nAPPLIED ' .. tostring(MUTANT.applied or 0) .. '/' .. #MUTANT.patches) or ''
return (ok and res or ('CRASH ' .. tostring(res))) .. tail
"@
    return [LuaRun]::Run($chunk)
}

if (-not $Prove) {
    $pre = if ($Only) { "ONLY = '" + $Only.Replace("'", "\'") + "'" } else { '' }
    $out = Invoke-Tests $pre
    $out
    $fails = ($out -split "`n" | Where-Object { $_ -match '^(FAIL|CRASH|ERROR)' }).Count
    $passes = ($out -split "`n" | Where-Object { $_ -match '^PASS' }).Count
    $known = ($out -split "`n" | Where-Object { $_ -match '^(KNOWN|FIXED\?)' }).Count
    # KNOWN = a real bug written up in test\FOUND_BUGS.md, not fixed yet (doesn't count as a failure)
    "`n$passes passed, $fails failed" + $(if ($known) { ", $known known bug(s) (test\FOUND_BUGS.md)" } else { '' })
    if ($fails -gt 0) { exit 1 }
    exit 0
}

# -Prove: each mutant must make its test fail
$list = [LuaRun]::Run(@"
local M = dofile('$mutants')
local out = {}
for i, m in ipairs(M) do out[#out + 1] = i .. '\t' .. m.test .. '\t' .. m.why end
return table.concat(out, '\n')
"@)
if ($list -match '^ERROR') { "mutants.lua: $list"; exit 1 }
$bad = 0
foreach ($line in ($list -split "`n")) {
    $parts = $line -split "`t"
    $i, $test, $why = $parts[0], $parts[1], $parts[2]
    $out = Invoke-Tests "MUTANT = dofile('$mutants')[$i]; ONLY = MUTANT.test"
    $rows = $out -split "`n"
    $applied = ($rows | Where-Object { $_ -match '^APPLIED' }) -replace 'APPLIED ', ''
    $result = ($rows | Where-Object { $_ -match '^(PASS|FAIL)' } | Select-Object -First 1)
    if ($out -match 'MUTANT PATCH NOT FOUND') { $verdict = 'STALE      '; $bad++ }
    elseif (-not $result) { $verdict = 'NO TEST    '; $bad++ }
    elseif ($applied -and [int](($applied -split '/')[0]) -lt [int](($applied -split '/')[1])) { $verdict = 'NOT LOADED '; $bad++ }
    elseif ($result -match '^FAIL') { $verdict = 'caught     ' }
    else { $verdict = 'NOT CAUGHT '; $bad++ }
    "$verdict [$test] without: $why"
    if ($verdict -ne 'caught     ') { "            $result" }
}
"`n$bad problem(s)"
if ($bad -gt 0) { exit 1 }
