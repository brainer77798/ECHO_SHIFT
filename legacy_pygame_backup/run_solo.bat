@echo off
title ECHO//SHIFT - Solo Mode
echo ==================================================
echo   Launching ECHO//SHIFT Solo Mode...
echo ==================================================

if exist ".\.venv\Scripts\python.exe" (
    ".\.venv\Scripts\python.exe" main.py
) else (
    python main.py
)

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Game exited with error code %ERRORLEVEL%.
    pause
)
