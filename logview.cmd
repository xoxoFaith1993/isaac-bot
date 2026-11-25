@echo off
title Isaac Bot log
rem Python comes from config.json ("python"), default: python on PATH
set "PY=python"
for /f "usebackq delims=" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\config.ps1" -Get python`) do set "PY=%%p"
"%PY%" "%~dp0brain\logview.py"
