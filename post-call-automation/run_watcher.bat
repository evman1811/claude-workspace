@echo off
cd /d "%~dp0"
echo Starting the call watcher for the whole team.
echo Leave this window open. Press Ctrl+C to stop.
echo.
python watch_folder.py
pause
