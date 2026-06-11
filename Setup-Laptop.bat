@echo off

:: Prüfen ob bereits als Admin gestartet
net session >nul 2>&1
if %errorLevel% == 0 goto :run

:: Nicht als Admin — UAC-Prompt auslösen und neu starten
echo Starte als Administrator...
powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:run
:: PowerShell starten mit Bypass und dem Skript im selben Verzeichnis wie diese .bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Laptop.ps1"
if %errorLevel% neq 0 (
    echo.
    echo FEHLER: Skript abgebrochen mit Code %errorLevel%
    pause
)
