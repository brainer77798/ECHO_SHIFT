@echo off
title ECHO//SHIFT - Client Launcher
echo ==================================================
echo   Launching ECHO//SHIFT Game Client...
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
