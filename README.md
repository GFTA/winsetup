# Startklar Setup

Automatisiertes Windows-Laptop-Setup-Tool fur Smartbar-Gerate. Fuhrt per Doppelklick folgende Schritte aus:

- WLAN-Verbindung herstellen (WPA2, Profil wird automatisch erstellt)
- Windows Updates installieren (BIOS/Firmware-Updates werden ubersprungen)
- Energieeinstellungen setzen (Monitor/Standby auf 60 min, Hochstleistung aktivieren)
- Programme installieren (alle `.msi`/`.exe` aus dem `Programs/`-Ordner)
- Autostart bereinigen (OneDrive, Phone Link, Xbox Game Bar, Copilot)
- Windows optimieren (Sticky Keys, Widgets, Telemetrie)

Nach jedem Durchlauf wird ein automatischer Neustart geplant und Updates erneut gepruft — solange bis keine Updates mehr ausstehen.

## Requirements

- Windows 10 / Windows 11
- Administratorrechte (werden automatisch per UAC angefordert)
- PowerShell-Modul `PSWindowsUpdate` (wird beim ersten Start automatisch installiert)

## Setup

1. `config.example.json` nach `config.json` kopieren:
   ```
   copy config.example.json config.json
   ```
2. `config.json` offnen und die Werte anpassen:
   - `WLAN.SSID` — Name des WLANs
   - `WLAN.Password` — WLAN-Passwort (ersetze `CHANGE_ME`)
3. Optionale Programme in den Ordner `Programs/` legen (`.msi` oder `.exe`).  
   Fur stille Installation eine `.args`-Datei mit gleichem Namen ablegen (z. B. `setup.exe.args` mit Inhalt `/S`).
4. `Setup-Laptop.bat` per Doppelklick starten — UAC-Prompt bestatigen, dann lauft alles automatisch.

## Screenshot

<!-- Screenshot hier einfugen -->

## Dateistruktur

```
Startklar Setup/
├── Setup-Laptop.bat       # Einstiegspunkt (Doppelklick)
├── Setup-Laptop.ps1       # Hauptskript
├── config.json            # Lokale Konfiguration (nicht im Repo)
├── config.example.json    # Vorlage fur config.json
└── Programs/              # Optionale Installationsdateien (.msi/.exe)
```
