@echo off
cd /d "%~dp0"
echo ============================================
echo   Post-Call Lead Scorer  -  one-time setup
echo ============================================
echo.

where python >nul 2>nul
if errorlevel 1 (
  echo Python is not installed yet.
  echo Get it free from https://www.python.org/downloads/
  echo IMPORTANT: during install, TICK the box "Add Python to PATH".
  echo Then run this setup again.
  echo.
  pause
  exit /b
)

echo Installing the libraries this tool needs (one time)...
python -m pip install -r requirements.txt
echo.

if not exist .env copy .env.example .env >nul

echo ============================================
echo   ONE STEP LEFT: paste your API key
echo ============================================
echo Notepad is about to open your settings file.
echo   1) Find the line that starts with   ANTHROPIC_API_KEY=
echo   2) Paste your key right after the =  (Ctrl+V)
echo   3) Save with Ctrl+S, then close Notepad
echo.
echo Paste into NOTEPAD - not this black window.
echo.
pause
notepad .env

echo.
echo Done. Next: double-click  test.bat  to score a sample call.
pause
