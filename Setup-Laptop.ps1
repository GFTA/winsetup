#Requires -RunAsAdministrator
param([switch]$AutoRun)

$Version = "1.1"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$sync = [hashtable]::Synchronized(@{})
$usbDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalDir = "C:\ProgramData\SmartbarSetup"
if (-not (Test-Path $LocalDir)) { New-Item -ItemType Directory -Path $LocalDir | Out-Null }

# Self-Copy: beim ersten Start von USB Dateien auf lokale Festplatte kopieren
# Danach kann der Stick entfernt werden - alle Folge-Reboots laufen von C:\
$sync.CopiedFromUsb = $false
if ($usbDir -ne $LocalDir) {
    foreach ($f in @("Setup-Laptop.ps1", "Setup-Laptop.bat", "config.json")) {
        $src = Join-Path $usbDir $f
        if (Test-Path $src) { Copy-Item $src $LocalDir -Force }
    }
    $progSrc = Join-Path $usbDir "Programs"
    if (Test-Path $progSrc) {
        Copy-Item $progSrc (Join-Path $LocalDir "Programs") -Recurse -Force
    }
    $sync.CopiedFromUsb = $true
}

# Geraete-Infos fuer Log-Dateinamen
$rawSN    = (Get-WmiObject Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
$rawModel = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
if (-not $rawSN -or $rawSN -match "Default|To Be Filled|Not Specified|^$") { $rawSN = "UNKNOWN" }
$sync.DeviceSN    = $rawSN.Trim() -replace '[\\/:*?"<>| ]', '_'
$sync.DeviceModel = if ($rawModel) { $rawModel.Trim() } else { "Unbekanntes Modell" }

# Log-Ziel: nur auf dem Stick (nicht auf Kundengeraet)
$sourcePathFile = Join-Path $LocalDir "source_path.txt"
if ($usbDir -ne $LocalDir) {
    # Von USB/Quelle gestartet: Pfad fuer AutoRun-Laeufe speichern
    Set-Content $sourcePathFile $usbDir -Encoding UTF8
    $logSource = $usbDir
} elseif (Test-Path $sourcePathFile) {
    # AutoRun-Lauf: gespeicherten Stick-Pfad lesen
    $saved = (Get-Content $sourcePathFile -Raw -ErrorAction SilentlyContinue).Trim()
    $logSource = if ($saved -and (Test-Path $saved)) { $saved } else { $LocalDir }
} else {
    $logSource = $LocalDir
}

# Ab jetzt immer von LocalDir aus arbeiten
$sync.ScriptDir   = $LocalDir
$sync.ProgramsDir = Join-Path $LocalDir "Programs"
$sync.LogDir      = Join-Path $LocalDir "Logs"   # immer lokal

# Config laden (WLAN, Autostart, ...)
$configFile = Join-Path $LocalDir "config.json"
$_cfg = $null
if (Test-Path $configFile) {
    try { $_cfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}
$sync.WlanSSID           = if ($_cfg -and $_cfg.WLAN -and $_cfg.WLAN.SSID)     { $_cfg.WLAN.SSID }           else { "CHANGE_ME" }
$sync.WlanPass           = if ($_cfg -and $_cfg.WLAN -and $_cfg.WLAN.Password) { $_cfg.WLAN.Password }       else { "CHANGE_ME" }
$sync.AutostartEntries   = if ($_cfg -and $_cfg.Autostart)                     { $_cfg.Autostart }           else { @() }
$sync.UpdateSkipPattern  = if ($_cfg -and $_cfg.UpdateSkipPattern)             { $_cfg.UpdateSkipPattern }   else { "BIOS|Firmware|System Firmware" }
if (-not (Test-Path $sync.LogDir)) { New-Item -ItemType Directory -Path $sync.LogDir | Out-Null }
$sync.LogFile         = Join-Path $sync.LogDir "$(Get-Date -Format 'yyyy-MM-dd')_$($sync.DeviceSN).txt"

# Logs aelter als 30 Tage loeschen
Get-ChildItem $sync.LogDir -Filter "*.txt" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force
$sync.AutoRun  = $AutoRun.IsPresent
$sync.TaskName = "SmartbarSetup"

# Durchlauf-Zaehler (lokal, nicht auf Stick)
$counterFile = Join-Path $sync.ScriptDir "setup_run.tmp"
if (Test-Path $counterFile) {
    $sync.RunCount = [int](Get-Content $counterFile -Raw) + 1
} else {
    $sync.RunCount = 1
}
Set-Content $counterFile $sync.RunCount

[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Smartbar Laptop Setup"
    Width="900" Height="620"
    MinWidth="900" MinHeight="620"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanResize"
    Background="#1e1e2e">
    <Window.Resources>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#6c7086"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Margin" Value="0,3,0,3"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Border x:Name="chkBox" Width="16" Height="16" CornerRadius="3"
                                    Background="#313244" BorderBrush="#45475a" BorderThickness="1.5"
                                    VerticalAlignment="Center">
                                <TextBlock x:Name="chkMark" Text="&#x2714;" FontSize="10" FontWeight="Bold"
                                           Foreground="#a6e3a1" HorizontalAlignment="Center"
                                           VerticalAlignment="Center" Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"
                                              TextElement.Foreground="{TemplateBinding Foreground}"
                                              RecognizesAccessKey="True"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="chkMark" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="chkBox" Property="BorderBrush" Value="#a6e3a1"/>
                                <Setter TargetName="chkBox" Property="Background" Value="#1e3a2a"/>
                                <Setter Property="Foreground" Value="#a6e3a1"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="chkBox" Property="BorderBrush" Value="#89b4fa"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="chkBox" Property="BorderBrush" Value="#313244"/>
                                <Setter TargetName="chkMark" Property="Foreground" Value="#45475a"/>
                                <Setter Property="Foreground" Value="#45475a"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#89b4fa"/>
            <Setter Property="Foreground" Value="#1e1e2e"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Height" Value="42"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="16,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#b4befe"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#45475a"/>
                                <Setter Property="Foreground" Value="#585b70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <!-- Normaler Setup-View -->
        <Grid x:Name="viewSetup">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="300"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Linke Seite: Optionen -->
            <Border Grid.Column="0" Background="#181825">
                <Grid Margin="24">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Header -->
                    <StackPanel Grid.Row="0" Margin="0,0,0,24">
                        <DockPanel>
                            <TextBlock Text="Smartbar Setup" FontSize="20" FontWeight="Bold" Foreground="#89b4fa"/>
                            <TextBlock x:Name="txtVersion" Text="" FontSize="11" Foreground="#45475a" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,0,2"/>
                        </DockPanel>
                        <TextBlock x:Name="txtRunCount" Text="" FontSize="11" Foreground="#6c7086" Margin="0,2,0,0"/>
                    </StackPanel>

                    <!-- Checkboxen -->
                    <StackPanel Grid.Row="1" Margin="0,0,0,24">
                        <TextBlock Text="SCHRITTE" FontSize="10" Foreground="#6c7086" FontWeight="Bold" Margin="0,0,0,10"/>
                        <CheckBox x:Name="chkWifi"     Content="WLAN verbinden" IsChecked="True"/>
                        <CheckBox x:Name="chkUpdates"  Content="Windows Updates" IsChecked="True"/>
                        <CheckBox x:Name="chkEnergy"   Content="Energieeinstellungen" IsChecked="True"/>
                        <CheckBox x:Name="chkCalman"   Content="Programme installieren" IsChecked="True"/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,2">
                            <CheckBox x:Name="chkOneDrive" Content="Autostart bereinigen" IsChecked="True" VerticalAlignment="Center"/>
                            <TextBlock x:Name="btnAutostartToggle" Text=" >" Foreground="#89b4fa"
                                       FontSize="12" Cursor="Hand" VerticalAlignment="Center" Margin="4,0,0,0"/>
                        </StackPanel>
                        <StackPanel x:Name="pnlAutostart" Margin="18,0,0,4" Visibility="Collapsed">
                            <CheckBox x:Name="chkAutoOneDrive"  Content="OneDrive"      IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                            <CheckBox x:Name="chkAutoPhoneLink" Content="Phone Link"    IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                            <CheckBox x:Name="chkAutoXbox"      Content="Xbox Game Bar" IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                            <CheckBox x:Name="chkAutoCopilot"   Content="Copilot"       IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                        </StackPanel>
                        <CheckBox x:Name="chkTweaks"   Content="Windows optimieren" IsChecked="True"/>
                    </StackPanel>

                    <!-- Fortschritt -->
                    <StackPanel Grid.Row="2" VerticalAlignment="Bottom" Margin="0,0,0,20">
                        <DockPanel Margin="0,0,0,8">
                            <TextBlock x:Name="txtStatus" Text="Bereit" FontSize="13" Foreground="#cdd6f4" VerticalAlignment="Center"/>
                            <TextBlock x:Name="txtStep" Text="" FontSize="11" Foreground="#6c7086" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </DockPanel>
                        <ProgressBar x:Name="progressBar" Height="8" Minimum="0" Maximum="100" Value="0"
                                     Background="#313244" Foreground="#89b4fa" BorderThickness="0">
                            <ProgressBar.Template>
                                <ControlTemplate TargetType="ProgressBar">
                                    <Border Background="{TemplateBinding Background}" CornerRadius="4">
                                        <Border x:Name="PART_Track">
                                            <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}"
                                                    HorizontalAlignment="Left" CornerRadius="4"/>
                                        </Border>
                                    </Border>
                                </ControlTemplate>
                            </ProgressBar.Template>
                        </ProgressBar>
                    </StackPanel>

                    <!-- Button + Footer -->
                    <Button x:Name="btnStart" Grid.Row="3" Content="Setup starten" Margin="0,0,0,10"/>
                    <TextBlock x:Name="txtFooter" Grid.Row="4" Text="" FontSize="10" Foreground="#6c7086" HorizontalAlignment="Center" TextWrapping="Wrap"/>
                </Grid>
            </Border>

            <!-- Rechte Seite: Log -->
            <Border Grid.Column="1" Background="#11111b" Margin="0">
                <ScrollViewer x:Name="logScroller" VerticalScrollBarVisibility="Auto" Margin="0">
                    <TextBlock x:Name="txtLog" FontFamily="Consolas" FontSize="13"
                               Foreground="#cdd6f4" Padding="20,16" TextWrapping="Wrap"/>
                </ScrollViewer>
            </Border>
        </Grid>

        <!-- Fertig-View (am Ende sichtbar) -->
        <Grid x:Name="viewDone" Visibility="Collapsed" Background="#1e1e2e">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                <TextBlock x:Name="txtDoneCheck" Text="&#10003;" FontSize="80" Foreground="#a6e3a1" HorizontalAlignment="Center"/>
                <TextBlock x:Name="txtDoneTitle" Text="Laptop fertig!" FontSize="32" FontWeight="Bold" Foreground="#a6e3a1"
                           HorizontalAlignment="Center" Margin="0,8,0,4"/>
                <TextBlock x:Name="txtDoneDetails" Text="" FontSize="14" Foreground="#6c7086"
                           HorizontalAlignment="Center" Margin="0,0,0,32" TextAlignment="Center"/>
                <Button x:Name="btnDoneOpenLog" Content="Log oeffnen" Width="200"
                        Background="#313244" Foreground="#cdd6f4" Margin="0,0,0,8"/>
                <Button x:Name="btnDoneClose" Content="Fenster schliessen" Width="200"
                        Background="#45475a" Foreground="#cdd6f4"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$sync.Window = [Windows.Markup.XamlReader]::Load($reader)

$sync.viewSetup     = $sync.Window.FindName("viewSetup")
$sync.viewDone      = $sync.Window.FindName("viewDone")
$sync.txtRunCount   = $sync.Window.FindName("txtRunCount")
$sync.txtVersion    = $sync.Window.FindName("txtVersion")
$sync.txtVersion.Text = "v$Version"
$sync.chkWifi       = $sync.Window.FindName("chkWifi")
$sync.chkEnergy     = $sync.Window.FindName("chkEnergy")
$sync.chkCalman     = $sync.Window.FindName("chkCalman")
$sync.chkOneDrive         = $sync.Window.FindName("chkOneDrive")
$sync.btnAutostartToggle  = $sync.Window.FindName("btnAutostartToggle")
$sync.ArrowRight = " " + [char]0x25B6   # ▶
$sync.ArrowDown  = " " + [char]0x25BC   # ▼
$sync.btnAutostartToggle.Text = $sync.ArrowRight
$sync.pnlAutostart        = $sync.Window.FindName("pnlAutostart")
$sync.chkAutoOneDrive  = $sync.Window.FindName("chkAutoOneDrive")
$sync.chkAutoPhoneLink = $sync.Window.FindName("chkAutoPhoneLink")
$sync.chkAutoXbox      = $sync.Window.FindName("chkAutoXbox")
$sync.chkAutoCopilot   = $sync.Window.FindName("chkAutoCopilot")
$sync.chkTweaks        = $sync.Window.FindName("chkTweaks")
$sync.chkUpdates    = $sync.Window.FindName("chkUpdates")
$sync.progressBar   = $sync.Window.FindName("progressBar")
$sync.txtStatus     = $sync.Window.FindName("txtStatus")
$sync.txtStep       = $sync.Window.FindName("txtStep")
$sync.txtLog        = $sync.Window.FindName("txtLog")
$sync.logScroller   = $sync.Window.FindName("logScroller")
$sync.btnStart      = $sync.Window.FindName("btnStart")
$sync.txtFooter     = $sync.Window.FindName("txtFooter")
$sync.txtDoneDetails  = $sync.Window.FindName("txtDoneDetails")
$sync.btnDoneOpenLog  = $sync.Window.FindName("btnDoneOpenLog")
$sync.btnDoneClose    = $sync.Window.FindName("btnDoneClose")

# Labels dynamisch befuellen
$sync.chkWifi.Content = "WLAN verbinden ($($sync.WlanSSID))"
$_progFiles = if (Test-Path $sync.ProgramsDir) {
    Get-ChildItem $sync.ProgramsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".msi", ".exe") }
} else { @() }
$_progCount = @($_progFiles).Count
if ($_progCount -gt 0) {
    $sync.chkCalman.Content = "Programme installieren ($_progCount)"
} else {
    $sync.chkCalman.Content   = "Programme installieren (keine)"
    $sync.chkCalman.IsChecked = $false
    $sync.chkCalman.IsEnabled = $false
}

# Durchlauf-Anzeige (nur im AutoRun-Modus)
if ($sync.AutoRun) {
    $sync.txtRunCount.Text = "Durchlauf $($sync.RunCount)"
} else {
    $sync.txtRunCount.Text = ""
}

# Im AutoRun-Modus: nur Updates, Checkboxen sperren
if ($sync.AutoRun) {
    $sync.chkWifi.IsChecked      = $false
    $sync.chkEnergy.IsChecked    = $false
    $sync.chkCalman.IsChecked    = $false
    $sync.chkOneDrive.IsChecked  = $false
    $sync.chkTweaks.IsChecked    = $false
    $sync.chkUpdates.IsChecked   = $true
    $sync.chkWifi.IsEnabled      = $false
    $sync.chkEnergy.IsEnabled    = $false
    $sync.chkCalman.IsEnabled    = $false
    $sync.chkOneDrive.IsEnabled  = $false
    $sync.pnlAutostart.IsEnabled = $false
    $sync.chkTweaks.IsEnabled    = $false
    $sync.chkUpdates.IsEnabled   = $false
}

# Autostart: Pfeil klappt Sub-Panel auf/zu
$sync.btnAutostartToggle.Add_MouseLeftButtonUp({
    if ($sync.pnlAutostart.Visibility -eq "Collapsed") {
        $sync.pnlAutostart.Visibility = "Visible"
        $sync.btnAutostartToggle.Text = $sync.ArrowDown
    } else {
        $sync.pnlAutostart.Visibility = "Collapsed"
        $sync.btnAutostartToggle.Text = $sync.ArrowRight
    }
})
# Eltern-Checkbox aktiviert/deaktiviert Sub-Optionen
$sync.chkOneDrive.Add_Click({
    $sync.pnlAutostart.IsEnabled = [bool]$sync.chkOneDrive.IsChecked
})

# Worker-Script
$sync.WorkerScript = {

    function Write-UILog {
        param([string]$Message, [string]$Level = "INFO")
        $ts   = Get-Date -Format "HH:mm:ss"
        $line = "[$ts] [$Level] $Message"
        Add-Content -Path $sync.LogFile -Value $line -ErrorAction SilentlyContinue
        $sync.Window.Dispatcher.Invoke([action]{
            $sync.txtLog.Text += "[$ts] $Message`n"
            $sync.logScroller.ScrollToBottom()
        }, "Normal")
    }

    function Out-Console {
        process { if ($_ -ne $null -and "$_".Trim()) { try { [Console]::WriteLine("  $_") } catch {} } }
    }

    function Set-UIProgress {
        param([int]$Percent, [string]$Status, [string]$Step = "")
        $sync.Window.Dispatcher.Invoke([action]{
            $sync.progressBar.Value = $Percent
            $sync.txtStatus.Text    = $Status
            $sync.txtStep.Text      = $Step
        }, "Normal")
    }

    function Register-AutoRunTask {
        $scriptPath = Join-Path $sync.ScriptDir "Setup-Laptop.ps1"
        $taskArg    = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -AutoRun"
        schtasks.exe /create /tn $sync.TaskName /tr $taskArg /sc onlogon /ru $env:USERNAME /rl highest /f | Out-Console
        Write-UILog "Auto-Neustart registriert (Aufgabenplanung)"
    }

    function Remove-AutoRunTask {
        schtasks.exe /delete /tn $sync.TaskName /f 2>$null | Out-Console
        Write-UILog "Auto-Neustart entfernt"
        $counterFile = Join-Path $sync.ScriptDir "setup_run.tmp"
        if (Test-Path $counterFile) { Remove-Item $counterFile -Force }
        # Setup-Ordner beim naechsten Login automatisch loeschen (RunOnce)
        $cleanCmd = "cmd /c rmdir /s /q `"$($sync.ScriptDir)`""
        reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "SmartbarCleanup" /t REG_SZ /d $cleanCmd /f | Out-Console
    }

    try {
        $totalSteps = 0
        if ($sync.DoWifi)     { $totalSteps++ }
        if ($sync.DoEnergy)   { $totalSteps++ }
        if ($sync.DoCalman)   { $totalSteps++ }
        if ($sync.DoOneDrive) { $totalSteps++ }
        if ($sync.DoTweaks)   { $totalSteps++ }
        if ($sync.DoUpdates)  { $totalSteps++ }
        if ($totalSteps -eq 0) { $totalSteps = 1 }
        $doneSteps       = 0
        $errCount        = 0
        $okCount         = 0
        $failedStepNames = [System.Collections.Generic.List[string]]::new()

        Write-UILog "=== Durchlauf $($sync.RunCount) auf $env:COMPUTERNAME ==="
        Write-UILog "Geraet: $($sync.DeviceModel)  |  SN: $($sync.DeviceSN)"

        # WLAN
        if ($sync.DoWifi) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "WLAN verbinden..." "Schritt $($doneSteps+1)/$totalSteps"
            Write-UILog "Verbinde mit WLAN $($sync.WlanSSID)..."
            try {
                $ssidPattern = [regex]::Escape($sync.WlanSSID)

                # Schon verbunden? Get-NetConnectionProfile ist locale-unabhaengig und
                # zuverlaessiger als netsh-Textparsung (kein BSSID/Encoding-Problem)
                $alreadyConn = $false
                try {
                    $alreadyConn = (Get-NetConnectionProfile -ErrorAction Stop).Name -contains $sync.WlanSSID
                } catch {
                    # Fallback: netsh zeilenweise (verhindert BSSID-Substring-Treffer)
                    foreach ($line in @(netsh wlan show interfaces)) {
                        if ($line -match "^\s+SSID\s+:\s+(.+)$" -and $line -notmatch "BSSID") {
                            $alreadyConn = ($matches[1].Trim() -eq $sync.WlanSSID)
                            break
                        }
                    }
                }
                if ($alreadyConn) {
                    Write-UILog "WLAN $($sync.WlanSSID) bereits verbunden" "OK"
                    $okCount++
                } else {
                    $wifiXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$($sync.WlanSSID)</name>
    <SSIDConfig><SSID><name>$($sync.WlanSSID)</name></SSID></SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$($sync.WlanPass)</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
                    $wifiXmlPath = Join-Path $env:TEMP "smartbar_wifi.xml"
                    Set-Content $wifiXmlPath $wifiXml -Encoding UTF8
                    netsh wlan add profile filename="$wifiXmlPath" user=all | Out-Console
                    Remove-Item $wifiXmlPath -Force -ErrorAction SilentlyContinue

                    # netsh wlan connect schlaegt elevated fehl (WlanGetAvailableNetworkList Error 5)
                    # Stattdessen: Adapter kurz deaktivieren -> WLAN-AutoConfig verbindet selbst
                    $wlanName = $null
                    foreach ($line in (netsh wlan show interfaces 2>$null)) {
                        if ($line -match "^\s+Name\s+:\s+(.+)") { $wlanName = $matches[1].Trim(); break }
                    }
                    if ($wlanName) {
                        Write-UILog "Adapter '$wlanName' neu starten..."
                        netsh interface set interface "$wlanName" disabled 2>$null | Out-Console
                        Start-Sleep 2
                        netsh interface set interface "$wlanName" enabled  2>$null | Out-Console
                        Start-Sleep 3
                    }

                    # Warten bis verbunden
                    Write-UILog "Warte auf WLAN-Verbindung..."
                    $maxWait   = 90
                    $waited    = 0
                    $connected = $false
                    while ($waited -lt $maxWait -and -not $connected) {
                        Start-Sleep 3
                        $waited += 3
                        try {
                            $connected = (Get-NetConnectionProfile -ErrorAction Stop).Name -contains $sync.WlanSSID
                        } catch {
                            foreach ($line in @(netsh wlan show interfaces)) {
                                if ($line -match "^\s+SSID\s+:\s+(.+)$" -and $line -notmatch "BSSID") {
                                    $connected = ($matches[1].Trim() -eq $sync.WlanSSID)
                                    break
                                }
                            }
                        }
                    }
                    if ($connected) {
                        Write-UILog "WLAN $($sync.WlanSSID) verbunden (nach $waited Sek)" "OK"
                        $okCount++
                    } else {
                        Write-UILog "WLAN: Timeout nach $maxWait Sek - Verbindung nicht bestaetigt" "WARN"
                        $okCount++
                    }
                }
            } catch {
                Write-UILog "Fehler WLAN: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("WLAN")
            }
            $doneSteps++
        }

        # Energieeinstellungen
        if ($sync.DoEnergy) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Energieeinstellungen..." "Schritt $($doneSteps+1)/$totalSteps"
            Write-UILog "Setze Energieeinstellungen..."
            $stepStart = Get-Date
            try {
                powercfg /change monitor-timeout-ac 60 | Out-Console
                powercfg /change monitor-timeout-dc 60 | Out-Console
                powercfg /change standby-timeout-ac 60 | Out-Console
                powercfg /change standby-timeout-dc 60 | Out-Console
                powercfg /change disk-timeout-ac    0  | Out-Console
                powercfg /change disk-timeout-dc    0  | Out-Console
                Write-UILog "Energieeinstellungen gesetzt ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                $okCount++
            } catch {
                Write-UILog "Fehler Energieeinstellungen: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Energieeinstellungen")
            }
            $doneSteps++
        }

        # Programme installieren
        if ($sync.DoCalman) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Programme installieren..." "Schritt $($doneSteps+1)/$totalSteps"
            Write-UILog "Installiere Programme..."
            $stepStart = Get-Date
            $progFiles = if (Test-Path $sync.ProgramsDir) {
                Get-ChildItem $sync.ProgramsDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in @(".msi", ".exe") } |
                    Sort-Object Name
            } else { @() }
            $progCount = ($progFiles | Measure-Object).Count
            if ($progCount -eq 0) {
                Write-UILog "Keine Programme im Programs-Ordner" "OK"
                $okCount++
            } else {
                $pi = 0
                foreach ($prog in $progFiles) {
                    $pi++
                    Write-UILog "  ($pi/$progCount) $($prog.Name)"
                    Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Installiere $($prog.BaseName)..." "Schritt $($doneSteps+1)/$totalSteps"
                    try {
                        $pLog = Join-Path $env:TEMP "$($prog.BaseName)_install.log"
                        if ($prog.Extension -eq ".msi") {
                            $pArgs = "/i `"$($prog.FullName)`" /qn /norestart /l*v `"$pLog`""
                            $proc  = Start-Process msiexec.exe -ArgumentList $pArgs -PassThru
                        } else {
                            $argsFile   = "$($prog.FullName).args"
                            $silentArgs = if (Test-Path $argsFile) { (Get-Content $argsFile -Raw -Encoding UTF8).Trim() } else { "/S" }
                            $proc = Start-Process $prog.FullName -ArgumentList $silentArgs -PassThru
                        }
                        $elapsed = 0
                        $pct = [int]($doneSteps / $totalSteps * 100)
                        while (-not $proc.HasExited) {
                            Start-Sleep 1; $elapsed++
                            Set-UIProgress $pct "Installiere $($prog.BaseName)... ($($elapsed)s)" "Schritt $($doneSteps+1)/$totalSteps"
                        }
                        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                            Write-UILog "  $($prog.BaseName) installiert ($($elapsed)s)" "OK"
                            $okCount++
                        } else {
                            Write-UILog "  $($prog.BaseName) Exit Code: $($proc.ExitCode)" "ERROR"
                            $errCount++
                            $failedStepNames.Add("Programm: $($prog.BaseName)")
                        }
                    } catch {
                        Write-UILog "  Fehler $($prog.BaseName): $_" "ERROR"
                        $errCount++
                        $failedStepNames.Add("Programm: $($prog.BaseName)")
                    }
                }
                Write-UILog "Programme fertig ($([int]((Get-Date)-$stepStart).TotalSeconds)s)"
            }
            $doneSteps++
        }

        # Autostart bereinigen
        if ($sync.DoOneDrive) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Autostart bereinigen..." "Schritt $($doneSteps+1)/$totalSteps"
            Write-UILog "Bereinige Autostart..."
            $stepStart = Get-Date
            try {
                $runKey  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
                $runKeyL = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"

                # Checkbox-Flags: welche Gruppen sind aktiv?
                $flagMap = @{
                    "OneDrive"  = $sync.DoAutoOneDrive
                    "PhoneLink" = $sync.DoAutoPhoneLink
                    "Xbox"      = $sync.DoAutoXbox
                    "Copilot"   = $sync.DoAutoCopilot
                }

                foreach ($entry in $sync.AutostartEntries) {
                    $doEntry = if ($flagMap.ContainsKey($entry.ID)) { $flagMap[$entry.ID] } else { $true }
                    if (-not $doEntry) { continue }

                    foreach ($key in $entry.Keys) {
                        foreach ($path in @($runKey, $runKeyL)) {
                            if ((Get-ItemProperty $path -ErrorAction SilentlyContinue).$key) {
                                Remove-ItemProperty $path -Name $key -Force -ErrorAction SilentlyContinue
                                Write-UILog "  $($entry.ID): $key aus Autostart entfernt"
                            }
                        }
                    }
                    if ($entry.Tasks) {
                        foreach ($task in $entry.Tasks) {
                            schtasks.exe /change /tn $task /disable 2>$null | Out-Console
                        }
                    }
                }

                Write-UILog "Autostart bereinigt ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                $okCount++
            } catch {
                Write-UILog "Fehler Autostart: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Autostart bereinigen")
            }
            $doneSteps++
        }

        # Windows optimieren
        if ($sync.DoTweaks) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Windows optimieren..." "Schritt $($doneSteps+1)/$totalSteps"
            Write-UILog "Optimiere Windows-Einstellungen..."
            $stepStart = Get-Date
            try {
                # Sticky Keys deaktivieren
                $stickyPath = "HKCU:\Control Panel\Accessibility\StickyKeys"
                $togglePath = "HKCU:\Control Panel\Accessibility\ToggleKeys"
                $filterPath = "HKCU:\Control Panel\Accessibility\Keyboard Response"
                if (-not (Test-Path $stickyPath)) { New-Item $stickyPath -Force | Out-Console }
                if (-not (Test-Path $togglePath)) { New-Item $togglePath -Force | Out-Console }
                if (-not (Test-Path $filterPath)) { New-Item $filterPath -Force | Out-Console }
                Set-ItemProperty $stickyPath -Name "Flags" -Value "506"  -Force
                Set-ItemProperty $togglePath -Name "Flags" -Value "58"   -Force
                Set-ItemProperty $filterPath -Name "Flags" -Value "122"  -Force
                Write-UILog "  Sticky Keys deaktiviert"

                # Widgets (Windows 11 Taskbar)
                $advPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Set-ItemProperty $advPath -Name "TaskbarDa" -Value 0 -Force -ErrorAction SilentlyContinue
                # News and Interests (Windows 10)
                $feedsPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds"
                if (-not (Test-Path $feedsPath)) { New-Item $feedsPath -Force | Out-Console }
                Set-ItemProperty $feedsPath -Name "ShellFeedsTaskbarViewMode" -Value 2 -Force -ErrorAction SilentlyContinue
                Write-UILog "  Widgets/News deaktiviert"

                # Telemetrie auf Minimum
                $telPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                if (-not (Test-Path $telPath)) { New-Item $telPath -Force | Out-Console }
                Set-ItemProperty $telPath -Name "AllowTelemetry" -Value 1 -Force
                $telPath2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
                if (-not (Test-Path $telPath2)) { New-Item $telPath2 -Force | Out-Console }
                Set-ItemProperty $telPath2 -Name "AllowTelemetry" -Value 1 -Force
                Write-UILog "  Telemetrie auf Minimum gesetzt"

                # Leistungsmodus: Hochstleistung aktivieren und setzen
                # GUID 8c5e7fda = Hohe Leistung; e9a42b02 = Ultimative Leistung (nur Desktop)
                $perfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
                powercfg /setactive $perfGuid 2>$null | Out-Console
                if ($LASTEXITCODE -ne 0) {
                    # Plan nicht vorhanden -> duplizieren
                    powercfg /duplicatescheme $perfGuid 2>$null | Out-Console
                    powercfg /setactive $perfGuid 2>$null | Out-Console
                }
                Write-UILog "  Leistungsmodus: Hohe Leistung aktiviert"

                Write-UILog "Windows optimiert ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                $okCount++
            } catch {
                Write-UILog "Fehler Windows-Optimierung: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Windows optimieren")
            }
            $doneSteps++
        }

        # Windows Updates
        $updatesInstalled = $false
        if ($sync.DoUpdates) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Windows Updates..." "Schritt $($doneSteps+1)/$totalSteps"

            # Internet-Check
            Write-UILog "Pruefe Internetverbindung..."
            $online = $false
            try {
                $null = [System.Net.WebClient]::new().DownloadString("http://www.msftconnecttest.com/connecttest.txt")
                $online = $true
                Write-UILog "Internetverbindung OK" "OK"
            } catch {
                Write-UILog "KEIN INTERNET - Windows Updates koennen nicht installiert werden!" "ERROR"
                Write-UILog "Bitte Netzwerkkabel/WLAN verbinden und erneut versuchen." "ERROR"
                $sync.Window.Dispatcher.Invoke([action]{
                    $sync.btnStart.Content      = "Erneut versuchen"
                    $sync.btnStart.IsEnabled    = $true
                    $sync.chkWifi.IsEnabled     = $true
                    $sync.chkEnergy.IsEnabled   = $true
                    $sync.chkCalman.IsEnabled   = $true
                    $sync.chkOneDrive.IsEnabled = $true
                    $sync.chkTweaks.IsEnabled   = $true
                    $sync.chkUpdates.IsEnabled  = $true
                    $sync.txtStatus.Text        = "Kein Internet!"
                }, "Normal")
                return
            }

            Write-UILog "Pruefe PSWindowsUpdate..."
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                try {
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Console
                    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber | Out-Console
                    Write-UILog "PSWindowsUpdate installiert" "OK"
                } catch {
                    Write-UILog "Fehler PSWindowsUpdate: $_" "ERROR"
                }
            }
            if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
                Import-Module PSWindowsUpdate
                Write-UILog "Suche nach Updates..."
                $stepStart = Get-Date
                try {
                    $skipPat  = $sync.UpdateSkipPattern
                    $allFound = @(Get-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue)
                    $skipped  = @($allFound | Where-Object { $_.Title -match $skipPat })
                    $updates  = @($allFound | Where-Object { $_.Title -notmatch $skipPat })

                    if ($skipped.Count -gt 0) {
                        Write-UILog "$($skipped.Count) Update(s) uebersprungen (werden beim Neustart angewendet):"
                        foreach ($s in $skipped) { Write-UILog "  [skip] $($s.Title)" }
                    }

                    $count   = $updates.Count
                    if ($count -gt 0) {
                        Write-UILog "$count Update(s) gefunden:"
                        $stepBase = [int]($doneSteps / $totalSteps * 100)
                        $stepSize = [int](1 / $totalSteps * 100)
                        $i = 0
                        foreach ($u in $updates) {
                            $i++
                            Write-UILog "  ($i/$count): $($u.Title)"
                        }

                        # KB-IDs der gefilterten Updates fuer Install-WU
                        $filteredKBs = @($updates | ForEach-Object {
                            if ($_.KBArticleIDs) { $_.KBArticleIDs } elseif ($_.KBArticleID) { $_.KBArticleID }
                        } | Where-Object { $_ } | Select-Object -Unique)

                        Write-UILog "Installiere $count Update(s)..."
                        Set-UIProgress $stepBase "Download laeuft..." "Schritt $($doneSteps+1)/$totalSteps"
                        $downloaded = 0
                        $installed  = 0
                        $barWidth   = 24

                        # Installation in separatem Runspace mit Timeout
                        # BIOS/Firmware bereits herausgefiltert - restliche Updates (inkl. .NET) bekommen 15 Min
                        $instQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
                        $instSync  = [hashtable]::Synchronized(@{ Done = $false; Error = $null })

                        $instRs = [runspacefactory]::CreateRunspace()
                        $instRs.ApartmentState = "STA"
                        $instRs.Open()
                        $instRs.SessionStateProxy.SetVariable("q",    $instQueue)
                        $instRs.SessionStateProxy.SetVariable("inst", $instSync)
                        $instRs.SessionStateProxy.SetVariable("kbs",  $filteredKBs)
                        $instRs.SessionStateProxy.SetVariable("skip", $skipPat)

                        $instPs = [powershell]::Create()
                        $instPs.Runspace = $instRs
                        [void]$instPs.AddScript({
                            try {
                                Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
                                if ($kbs -and $kbs.Count -gt 0) {
                                    Install-WindowsUpdate -KBArticleID $kbs -AcceptAll -IgnoreReboot -Confirm:$false |
                                        ForEach-Object { $q.Enqueue($_) }
                                } else {
                                    Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false -NotTitle $skip |
                                        ForEach-Object { $q.Enqueue($_) }
                                }
                            } catch {
                                $inst.Error = $_.ToString()
                            }
                            $inst.Done = $true
                        })
                        [void]$instPs.BeginInvoke()

                        $instMax  = 900   # 15 Minuten Timeout (z.B. grosse .NET Updates)
                        $instElap = 0
                        $qItem    = $null

                        while (-not $instSync.Done -and $instElap -lt $instMax) {
                            Start-Sleep 2; $instElap += 2
                            while ($instQueue.TryDequeue([ref]$qItem)) {
                                $statusStr = "$($qItem.Status)"
                                if ($statusStr -match '[DI]') {
                                    try { [Console]::WriteLine("  [$statusStr] $($qItem.Title)") } catch {}
                                }
                                if ($statusStr -match 'D' -and $statusStr -notmatch 'I') {
                                    $downloaded++
                                    $filled = [int]($downloaded / $count * $barWidth)
                                    $bar    = ('#' * $filled) + ('-' * ($barWidth - $filled))
                                    $pct    = $stepBase + [int]($downloaded / $count * $stepSize * 0.5)
                                    $uTitle = if ($qItem.Title.Length -gt 35) { $qItem.Title.Substring(0,35) + "..." } else { $qItem.Title }
                                    Write-UILog "  [DL $bar] $downloaded/$count  $uTitle"
                                    Set-UIProgress $pct "Download $downloaded/$count..." "Schritt $($doneSteps+1)/$totalSteps"
                                } elseif ($statusStr -match 'I') {
                                    $installed++
                                    $filled = [int]($installed / $count * $barWidth)
                                    $bar    = ('#' * $filled) + ('-' * ($barWidth - $filled))
                                    try { [Console]::WriteLine("  [$bar] $installed/$count") } catch {}
                                    $pct    = $stepBase + [int]($stepSize * 0.5 + $installed / $count * $stepSize * 0.5)
                                    $uTitle = if ($qItem.Title.Length -gt 35) { $qItem.Title.Substring(0,35) + "..." } else { $qItem.Title }
                                    Write-UILog "  [IN $bar] $installed/$count  $uTitle"
                                    Set-UIProgress $pct "Install $installed/$count..." "Schritt $($doneSteps+1)/$totalSteps"
                                }
                            }
                            # Fallback-Anzeige wenn kein neues Item (z.B. haengender Update)
                            $dispPct = [Math]::Min($stepBase + [int]($instElap / $instMax * $stepSize), 99)
                            Set-UIProgress $dispPct "Updates laufen... ($instElap s)" "Schritt $($doneSteps+1)/$totalSteps"
                        }

                        # Queue final leeren
                        while ($instQueue.TryDequeue([ref]$qItem)) {
                            $statusStr = "$($qItem.Status)"
                            if ($statusStr -match 'I') { $installed++ }
                            if ($statusStr -match 'D' -and $statusStr -notmatch 'I') { $downloaded++ }
                        }

                        try { $instPs.Stop() } catch {}
                        try { $instPs.Dispose(); $instRs.Close(); $instRs.Dispose() } catch {}

                        if (-not $instSync.Done) {
                            Write-UILog "Update-Timeout nach $($instMax / 60) Min - Update haengt (Neustart wird trotzdem geplant)" "WARN"
                        }
                        if ($instSync.Error) {
                            Write-UILog "Install-Fehler: $($instSync.Error)" "ERROR"
                        }
                        Write-UILog "$count Update(s) verarbeitet ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                        $updatesInstalled = $true
                        $okCount++
                    }
                    # Kein Update gefunden: trotzdem Reboot ausstehend?
                    if (-not $updatesInstalled) {
                        try {
                            $rebootNeeded = (Get-WURebootStatus -Silent -ErrorAction SilentlyContinue)
                            if ($rebootNeeded) {
                                Write-UILog "Neustart ausstehend (Updates warten auf Installation)" "OK"
                                $updatesInstalled = $true
                            }
                        } catch {}
                        if (-not $updatesInstalled) {
                            Write-UILog "Keine ausstehenden Updates" "OK"
                        }
                        $okCount++
                    }
                } catch {
                    Write-UILog "Fehler Updates: $_" "ERROR"
                    $errCount++
                    $failedStepNames.Add("Windows Updates")
                }
            } else {
                Write-UILog "PSWindowsUpdate nicht verfuegbar" "ERROR"
                $errCount++
                $failedStepNames.Add("Windows Updates")
            }
            $doneSteps++
        }

        Set-UIProgress 100 "Abgeschlossen" ""

        # Neustart-Entscheidung:
        # - Updates installiert           -> immer neu starten
        # - Erster Durchlauf (kein AutoRun) -> Sicherheits-Neustart auch ohne Updates
        # - AutoRun-Durchlauf, keine Updates -> fertig
        $doRestart = $updatesInstalled -or (-not $sync.AutoRun)

        if ($doRestart) {
            if ($updatesInstalled) {
                Write-UILog "Updates installiert - registriere Auto-Neustart..."
            } else {
                Write-UILog "Erster Durchlauf abgeschlossen - Sicherheits-Neustart + Update-Scan..." "OK"
            }
            Register-AutoRunTask
            Write-UILog "Neustart in 15 Sekunden..." "OK"

            # Countdown
            for ($i = 15; $i -ge 1; $i--) {
                $ii = $i
                $sync.Window.Dispatcher.Invoke([action]{
                    $sync.txtFooter.Text   = "Neustart in $ii Sekunden..."
                    $sync.btnStart.Content = "Jetzt neu starten"
                    $sync.btnStart.IsEnabled = $true
                }, "Normal")
                Start-Sleep -Seconds 1
            }
            shutdown.exe /r /t 0

        } else {
            # AutoRun-Durchlauf, keine Updates mehr -> fertig!
            Remove-AutoRunTask
            Write-UILog "=== Laptop bereit! ===" "OK"

            $runCount   = $sync.RunCount
            $logFile    = $sync.LogFile
            $winColor   = if ($errCount -gt 0) { "#2e1a1a" } else { "#1a2e1a" }
            $checkColor = if ($errCount -gt 0) { "#f38ba8" } else { "#a6e3a1" }

            if ($errCount -gt 0) {
                $uniqueFailed = ($failedStepNames | Select-Object -Unique)
                $failedLines  = ($uniqueFailed | ForEach-Object { "  - $_" }) -join "`n"
                $summaryLine  = "$okCount OK  |  $errCount Fehler:`n$failedLines"
            } else {
                $summaryLine  = "Alle $okCount Schritte erfolgreich"
            }
            $detailsText = "$summaryLine`n`n$runCount Durchlauf/Durchlaeufe`nLog: $logFile"

            $sync.Window.Dispatcher.Invoke([action]{
                $conv = [Windows.Media.BrushConverter]::new()
                $sync.Window.FindName("txtDoneCheck").Foreground = $conv.ConvertFromString($checkColor)
                $sync.txtDoneDetails.Text  = $detailsText
                $sync.viewSetup.Visibility = "Collapsed"
                $sync.viewDone.Visibility  = "Visible"
                $sync.Window.Background    = $conv.ConvertFromString($winColor)
            }, "Normal")
        }

    } catch {
        $err = $_.ToString()
        Add-Content -Path $sync.LogFile -Value "[CRASH] $err" -ErrorAction SilentlyContinue
        $sync.Window.Dispatcher.Invoke([action]{
            $sync.txtLog.Text    += "[CRASH] $err`n"
            $sync.txtStatus.Text  = "Fehler - siehe Log"
            $sync.btnStart.IsEnabled = $true
        }, "Normal")
    }
}

# Button: Setup starten / Neu starten
$sync.btnStart.Add_Click({
    if ($sync.btnStart.Content -eq "Jetzt neu starten") {
        shutdown.exe /r /t 0
        return
    }

    $sync.txtFooter.Text = ""

    $sync.DoWifi          = [bool]$sync.chkWifi.IsChecked
    $sync.DoEnergy        = [bool]$sync.chkEnergy.IsChecked
    $sync.DoCalman        = [bool]$sync.chkCalman.IsChecked
    $sync.DoOneDrive      = [bool]$sync.chkOneDrive.IsChecked
    $sync.DoAutoOneDrive  = [bool]$sync.chkAutoOneDrive.IsChecked
    $sync.DoAutoPhoneLink = [bool]$sync.chkAutoPhoneLink.IsChecked
    $sync.DoAutoXbox      = [bool]$sync.chkAutoXbox.IsChecked
    $sync.DoAutoCopilot   = [bool]$sync.chkAutoCopilot.IsChecked
    $sync.DoTweaks        = [bool]$sync.chkTweaks.IsChecked
    $sync.DoUpdates       = [bool]$sync.chkUpdates.IsChecked

    $sync.btnStart.IsEnabled     = $false
    $sync.chkWifi.IsEnabled      = $false
    $sync.chkEnergy.IsEnabled    = $false
    $sync.chkCalman.IsEnabled    = $false
    $sync.chkOneDrive.IsEnabled  = $false
    $sync.pnlAutostart.IsEnabled = $false
    $sync.chkTweaks.IsEnabled    = $false
    $sync.chkUpdates.IsEnabled   = $false

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("sync", $sync)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($sync.WorkerScript)
    [void]$ps.BeginInvoke()
})

# Fertig-View: Log oeffnen
$sync.btnDoneOpenLog.Add_Click({
    if (Test-Path $sync.LogFile) {
        Start-Process notepad.exe $sync.LogFile
    }
})

# Fertig-View: Schliessen-Button
$sync.btnDoneClose.Add_Click({
    $sync.Window.Close()
})

# AutoRun: sofort loslegen
if ($sync.AutoRun) {
    $sync.btnStart.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
}

if ($sync.CopiedFromUsb) {
    $sync.txtLog.Text = "[OK] Dateien nach C:\ProgramData\SmartbarSetup kopiert`n[>>] Stick kann jetzt entfernt werden`n`n"
    $sync.txtFooter.Text = "Stick kann entfernt werden"
}


$sync.Window.ShowDialog() | Out-Null
