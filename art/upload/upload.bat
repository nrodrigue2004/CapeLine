@echo off
rem Capeline art upload: double-click me. Reads Documents\roblox-keys\capeline-key.txt, never prints or saves the key.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload.ps1"
echo.
echo Done. Attach ids.json from this folder in the Capeline chat.
pause
