@echo off
title ECHO//SHIFT - Dedicated LAN Server
echo ==================================================
echo   Starting ECHO//SHIFT Authoritative LAN Server...
echo ==================================================

if exist ".\.venv\Scripts\python.exe" (
    ".\.venv\Scripts\python.exe" server.py --host 0.0.0.0 --port 42424
) else (
    python server.py --host 0.0.0.0 --port 42424
)

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Server exited with error code %ERRORLEVEL%.
    pause
)
