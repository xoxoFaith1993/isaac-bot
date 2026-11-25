@echo off
title Isaac Bot restart
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_bot.ps1" -Restart
timeout /t 5 >nul
