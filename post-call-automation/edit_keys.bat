@echo off
cd /d "%~dp0"
if not exist .env copy .env.example .env >nul
echo Opening your settings file in Notepad...
echo Paste your key after ANTHROPIC_API_KEY=  then Save (Ctrl+S) and close.
notepad .env
