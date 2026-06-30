@echo off
cd /d "%~dp0"
if "%~1"=="" (
  echo To score a call: DRAG a transcript .txt file onto this file.
  echo.
  pause
  exit /b
)
python run_call.py --transcript "%~1"
echo.
pause
