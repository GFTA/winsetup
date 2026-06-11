# Startklar Setup

Automated Windows provisioning and update tool — deploys a consistent baseline across multiple machines from a single USB stick. Each run installs pending updates and restarts automatically until the machine is fully up to date.

Steps performed on each run:

- Connect to Wi-Fi (WPA2, profile is created automatically)
- Install Windows Updates (BIOS/firmware updates are skipped)
- Configure power settings (monitor/standby set to 60 min, High performance mode activated)
- Install programs (all `.msi`/`.exe` files from the `Programs/` folder)
- Clean up autostart (OneDrive, Phone Link, Xbox Game Bar, Copilot)
- Optimize Windows (Sticky Keys, Widgets, Telemetry)

## Requirements

- Windows 10 / Windows 11
- Administrator rights (automatically requested via UAC)
- PowerShell module `PSWindowsUpdate` (installed automatically on first run)

## Getting started

1. Copy `config.example.json` to `config.json`:
   ```
   copy config.example.json config.json
   ```
2. Open `config.json` and fill in your values:
   - `WLAN.SSID` — Wi-Fi network name
   - `WLAN.Password` — Wi-Fi password (replace `CHANGE_ME`)
3. Optionally place programs in the `Programs/` folder (`.msi` or `.exe`).  
   For silent installation, add an `.args` file with the same base name (e.g. `setup.exe.args` containing `/S`).
4. Double-click `Setup-Laptop.bat` — confirm the UAC prompt, everything runs automatically.

## Screenshot

<!-- Insert screenshot here -->

## File structure

```
Startklar Setup/
├── Setup-Laptop.bat       # Entry point (double-click)
├── Setup-Laptop.ps1       # Main script
├── config.json            # Local configuration (not in repo)
├── config.example.json    # Template for config.json
└── Programs/              # Optional installation files (.msi/.exe)
```
