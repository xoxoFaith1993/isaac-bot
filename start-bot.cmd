@echo off
title Isaac Bot start
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_bot.ps1"
timeout /t 8 >nul
