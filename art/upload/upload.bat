@echo off
rem Capeline art upload: double-click me. Reads Documents\roblox-keys\capeline-key.txt, never prints or saves the key.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload.ps1"
echo.
echo Done. Next: paste resolve_ids.txt into the Studio command bar (README step 3), then attach ids.json and image_ids.txt in the Capeline chat.
pause
