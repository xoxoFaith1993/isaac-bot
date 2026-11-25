# Compile every Lua file of the bot with Isaac's own Lua engine, WITHOUT the game, before a reload or restart.
# Catches syntax errors (the kind that left the game stuck on the title screen, 2026-11-25) in about a second.
# Idea from an earlier Isaac mod's offline test runner.
# The DLL is 32-bit, so this needs 32-bit PowerShell:
#   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File tools\luacheck.ps1
param([string]$Game = '')   # default: game_dir from config.json

$root = Split-Path -Parent $PSScriptRoot
if (-not $Game) { . (Join-Path $PSScriptRoot 'config.ps1'); $Game = (Get-BotConfig).game_dir }
$dll = (Join-Path $Game 'Lua5.3.3r.dll').Replace('\', '\\')

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class LuaCheck {
    const string D = "$dll";
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr luaL_newstate();
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern void lua_close(IntPtr L);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern int luaL_loadbufferx(IntPtr L, byte[] buf, UIntPtr size, string name, string mode);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr lua_tolstring(IntPtr L, int i, IntPtr len);
    public static string Compile(byte[] code, string name) {
        IntPtr L = luaL_newstate();
        int rc = luaL_loadbufferx(L, code, (UIntPtr)code.Length, "@" + name, null);
        string msg = rc == 0 ? "" : Marshal.PtrToStringAnsi(lua_tolstring(L, -1, IntPtr.Zero));
        lua_close(L);
        return msg;
    }
}
"@

$files = Get-ChildItem (Join-Path $root 'mod') -Recurse -Filter *.lua
$bad = 0
foreach ($f in $files) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Output "FAIL $($f.Name): starts with a byte-order mark (Isaac's Lua can't read it)"
        $bad++
        continue
    }
    $err = [LuaCheck]::Compile($bytes, $f.Name)
    if ($err) { Write-Output "FAIL $err"; $bad++ }
}
if ($bad -eq 0) { Write-Output "OK: $($files.Count) Lua files compile" } else { Write-Output "$bad file(s) FAILED"; exit 1 }
