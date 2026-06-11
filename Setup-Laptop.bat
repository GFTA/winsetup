@echo off

:: Check if already running as Administrator
net session >nul 2>&1
if %errorLevel% == 0 goto :run

:: Not running as Admin - trigger UAC prompt and relaunch
echo Starting as Administrator...
powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:run
:: Launch PowerShell with Bypass and the script in the same directory as this .bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Laptop.ps1"
if %errorLevel% neq 0 (
    echo.
    echo ERROR: Script aborted with code %errorLevel%
    pause
)
