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

# Self-copy: on first run from USB, copy files to local hard drive
# After that the USB drive can be removed - all subsequent reboots run from C:\
$sync.CopiedFromUsb = $false
if ($usbDir -ne $LocalDir) {
    foreach ($f in @("Setup-Laptop.ps1", "Setup-Laptop.bat", "config.json")) {
        $src = Join-Path $usbDir $f
        if (Test-Path $src) { Copy-Item $src $LocalDir -Force }
    }
    $progSrc = Join-Path $usbDir "Programs"
    if (Test-Path $progSrc) {
        $progDst = Join-Path $LocalDir "Programs"
        New-Item -ItemType Directory $progDst -Force | Out-Null
        Copy-Item "$progSrc\*" $progDst -Recurse -Force
    }
    $sync.CopiedFromUsb = $true
}

# Device info for log file names
$rawSN    = (Get-WmiObject Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
$rawModel = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
if (-not $rawSN -or $rawSN -match "Default|To Be Filled|Not Specified|^$") { $rawSN = "UNKNOWN" }
$sync.DeviceSN    = $rawSN.Trim() -replace '[\\/:*?"<>| ]', '_'
$sync.DeviceModel = if ($rawModel) { $rawModel.Trim() } else { "Unknown model" }

# Log destination: always local
$sourcePathFile = Join-Path $LocalDir "source_path.txt"
if ($usbDir -ne $LocalDir) {
    Set-Content $sourcePathFile $usbDir -Encoding UTF8
    $logSource = $usbDir
} elseif (Test-Path $sourcePathFile) {
    $saved = (Get-Content $sourcePathFile -Raw -ErrorAction SilentlyContinue).Trim()
    $logSource = if ($saved -and (Test-Path $saved)) { $saved } else { $LocalDir }
} else {
    $logSource = $LocalDir
}

$sync.ScriptDir   = $LocalDir
$sync.ProgramsDir = Join-Path $LocalDir "Programs"
$sync.LogDir      = Join-Path $LocalDir "Logs"

# Load config (WLAN, Autostart, ...)
$configFile = Join-Path $LocalDir "config.json"
$_cfg = $null
if (Test-Path $configFile) {
    try { $_cfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}
$sync.WlanSSID           = if ($_cfg -and $_cfg.WLAN -and $_cfg.WLAN.SSID)     { $_cfg.WLAN.SSID }           else { "CHANGE_ME" }
$sync.WlanPass           = if ($_cfg -and $_cfg.WLAN -and $_cfg.WLAN.Password) { $_cfg.WLAN.Password }       else { "CHANGE_ME" }
$sync.AutostartEntries   = if ($_cfg -and $_cfg.Autostart)                     { $_cfg.Autostart }           else { @() }
$sync.UninstallEntries   = if ($_cfg -and $_cfg.Uninstall)                     { $_cfg.Uninstall }           else { @() }
$sync.UpdateSkipPattern  = if ($_cfg -and $_cfg.UpdateSkipPattern)             { $_cfg.UpdateSkipPattern }   else { "BIOS|Firmware|System Firmware" }
$sync.RegionTimeZone     = if ($_cfg -and $_cfg.Region -and $_cfg.Region.TimeZone) { $_cfg.Region.TimeZone }   else { "W. Europe Standard Time" }
$sync.RegionGeoId        = if ($_cfg -and $_cfg.Region -and $_cfg.Region.GeoId)    { [int]$_cfg.Region.GeoId } else { 14 }
$sync.RegionLocale       = if ($_cfg -and $_cfg.Region -and $_cfg.Region.Locale)   { $_cfg.Region.Locale }     else { "de-AT" }
if (-not (Test-Path $sync.LogDir)) { New-Item -ItemType Directory -Path $sync.LogDir | Out-Null }
$sync.LogFile = Join-Path $sync.LogDir "$(Get-Date -Format 'yyyy-MM-dd')_$($sync.DeviceSN).txt"

# Delete logs older than 30 days
Get-ChildItem $sync.LogDir -Filter "*.txt" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force
$sync.AutoRun  = $AutoRun.IsPresent
$sync.TaskName = "SmartbarSetup"

# Run counter
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
    Background="#2b2b2b">
    <Window.Resources>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#9a9a9a"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Margin" Value="0,3,0,3"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Border x:Name="chkBox" Width="16" Height="16" CornerRadius="3"
                                    Background="#3a3a3a" BorderBrush="#555555" BorderThickness="1.5"
                                    VerticalAlignment="Center">
                                <TextBlock x:Name="chkMark" Text="&#x2714;" FontSize="10" FontWeight="Bold"
                                           Foreground="#89b4fa" HorizontalAlignment="Center"
                                           VerticalAlignment="Center" Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"
                                              TextElement.Foreground="{TemplateBinding Foreground}"
                                              RecognizesAccessKey="True"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="chkMark" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="chkBox" Property="BorderBrush" Value="#89b4fa"/>
                                <Setter TargetName="chkBox" Property="Background" Value="#1a2a40"/>
                                <Setter Property="Foreground" Value="#89b4fa"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="chkBox" Property="BorderBrush" Value="#b4befe"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="chkBox" Property="BorderBrush" Value="#3a3a3a"/>
                                <Setter TargetName="chkMark" Property="Foreground" Value="#555555"/>
                                <Setter Property="Foreground" Value="#555555"/>
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
        <!-- Main setup view -->
        <Grid x:Name="viewSetup">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="300"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Left side: Options -->
            <Border Grid.Column="0" Background="#222222">
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
                            <TextBlock x:Name="txtVersion" Text="" FontSize="11" Foreground="#666666" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,0,2"/>
                        </DockPanel>
                        <TextBlock x:Name="txtRunCount" Text="" FontSize="11" Foreground="#777777" Margin="0,2,0,0"/>
                    </StackPanel>

                    <!-- Checkboxes -->
                    <StackPanel Grid.Row="1" Margin="0,0,0,24">
                        <TextBlock Text="STEPS" FontSize="10" Foreground="#777777" FontWeight="Bold" Margin="0,0,0,10"/>
                        <CheckBox x:Name="chkWifi"     Content="Connect Wi-Fi" IsChecked="True"/>
                        <CheckBox x:Name="chkUpdates"  Content="Windows Updates" IsChecked="True"/>
                        <CheckBox x:Name="chkEnergy"   Content="Power settings" IsChecked="True"/>
                        <CheckBox x:Name="chkCalman"    Content="Install programs" IsChecked="True"/>
                        <CheckBox x:Name="chkUninstall" Content="Uninstall apps" IsChecked="True"/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,2">
                            <CheckBox x:Name="chkOneDrive" Content="Clean up autostart" IsChecked="True" VerticalAlignment="Center"/>
                            <TextBlock x:Name="btnAutostartToggle" Text=" >" Foreground="#89b4fa"
                                       FontSize="12" Cursor="Hand" VerticalAlignment="Center" Margin="4,0,0,0"/>
                        </StackPanel>
                        <StackPanel x:Name="pnlAutostart" Margin="18,0,0,4" Visibility="Collapsed">
                            <CheckBox x:Name="chkAutoOneDrive"  Content="OneDrive"      IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                            <CheckBox x:Name="chkAutoPhoneLink" Content="Phone Link"    IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                            <CheckBox x:Name="chkAutoXbox"      Content="Xbox Game Bar" IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                            <CheckBox x:Name="chkAutoCopilot"   Content="Copilot"       IsChecked="True" FontSize="12" Margin="0,2,0,2"/>
                        </StackPanel>
                        <CheckBox x:Name="chkTweaks"   Content="Optimize Windows" IsChecked="True"/>
                    </StackPanel>

                    <!-- Progress -->
                    <StackPanel Grid.Row="2" VerticalAlignment="Bottom" Margin="0,0,0,20">
                        <DockPanel Margin="0,0,0,8">
                            <TextBlock x:Name="txtStatus" Text="Ready" FontSize="13" Foreground="#dddddd" VerticalAlignment="Center"/>
                            <TextBlock x:Name="txtStep" Text="" FontSize="11" Foreground="#777777" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </DockPanel>
                        <ProgressBar x:Name="progressBar" Height="8" Minimum="0" Maximum="100" Value="0"
                                     Background="#3a3a3a" Foreground="#89b4fa" BorderThickness="0">
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
                    <Button x:Name="btnStart" Grid.Row="3" Content="Start setup" Margin="0,0,0,10"/>
                    <TextBlock x:Name="txtFooter" Grid.Row="4" Text="" FontSize="10" Foreground="#777777" HorizontalAlignment="Center" TextWrapping="Wrap"/>
                </Grid>
            </Border>

            <!-- Right side: Log -->
            <Border Grid.Column="1" Background="#1e1e1e" Margin="0">
                <ScrollViewer x:Name="logScroller" VerticalScrollBarVisibility="Auto" Margin="0">
                    <TextBlock x:Name="txtLog" FontFamily="Consolas" FontSize="13"
                               Foreground="#cccccc" Padding="20,16" TextWrapping="Wrap"/>
                </ScrollViewer>
            </Border>
        </Grid>

        <!-- Done view (visible at the end) -->
        <Grid x:Name="viewDone" Visibility="Collapsed" Background="#2b2b2b">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                <TextBlock x:Name="txtDoneCheck" Text="&#10003;" FontSize="80" Foreground="#a6e3a1" HorizontalAlignment="Center"/>
                <TextBlock x:Name="txtDoneTitle" Text="Laptop ready!" FontSize="32" FontWeight="Bold" Foreground="#a6e3a1"
                           HorizontalAlignment="Center" Margin="0,8,0,4"/>
                <TextBlock x:Name="txtDoneDetails" Text="" FontSize="14" Foreground="#888888"
                           HorizontalAlignment="Center" Margin="0,0,0,32" TextAlignment="Center"/>
                <Button x:Name="btnDoneOpenLog" Content="Open log" Width="200"
                        Background="#3a3a3a" Foreground="#dddddd" Margin="0,0,0,8"/>
                <Button x:Name="btnDoneClose" Content="Close window" Width="200"
                        Background="#4a4a4a" Foreground="#dddddd"/>
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
$sync.ArrowRight = " " + [char]0x25B6
$sync.ArrowDown  = " " + [char]0x25BC
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
$sync.chkUninstall    = $sync.Window.FindName("chkUninstall")
$sync.txtDoneDetails  = $sync.Window.FindName("txtDoneDetails")
$sync.btnDoneOpenLog  = $sync.Window.FindName("btnDoneOpenLog")
$sync.btnDoneClose    = $sync.Window.FindName("btnDoneClose")

# Populate labels dynamically
$sync.chkWifi.Content = "Connect Wi-Fi ($($sync.WlanSSID))"
$_progFiles = if (Test-Path $sync.ProgramsDir) {
    Get-ChildItem $sync.ProgramsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".msi", ".exe") }
} else { @() }
$_progCount = @($_progFiles).Count
if ($_progCount -gt 0) {
    $sync.chkCalman.Content = "Install programs ($_progCount)"
} else {
    $sync.chkCalman.Content   = "Install programs (none)"
    $sync.chkCalman.IsChecked = $false
    $sync.chkCalman.IsEnabled = $false
}

# Uninstall label
$_uninstCount = @($sync.UninstallEntries).Count
if ($_uninstCount -gt 0) {
    $sync.chkUninstall.Content = "Uninstall apps ($_uninstCount)"
} else {
    $sync.chkUninstall.Content   = "Uninstall apps (none)"
    $sync.chkUninstall.IsChecked = $false
    $sync.chkUninstall.IsEnabled = $false
}

# Run counter display (AutoRun mode only)
if ($sync.AutoRun) {
    $sync.txtRunCount.Text = "Run $($sync.RunCount)"
} else {
    $sync.txtRunCount.Text = ""
}

# In AutoRun mode: updates only, lock checkboxes
if ($sync.AutoRun) {
    $sync.chkWifi.IsChecked      = $false
    $sync.chkEnergy.IsChecked    = $false
    $sync.chkCalman.IsChecked    = $false
    $sync.chkOneDrive.IsChecked   = $false
    $sync.chkUninstall.IsChecked  = $false
    $sync.chkTweaks.IsChecked     = $false
    $sync.chkUpdates.IsChecked    = $true
    $sync.chkWifi.IsEnabled       = $false
    $sync.chkEnergy.IsEnabled     = $false
    $sync.chkCalman.IsEnabled     = $false
    $sync.chkOneDrive.IsEnabled   = $false
    $sync.pnlAutostart.IsEnabled  = $false
    $sync.chkUninstall.IsEnabled  = $false
    $sync.chkTweaks.IsEnabled     = $false
    $sync.chkUpdates.IsEnabled    = $false
}

# Autostart: arrow expands/collapses sub-panel
$sync.btnAutostartToggle.Add_MouseLeftButtonUp({
    if ($sync.pnlAutostart.Visibility -eq "Collapsed") {
        $sync.pnlAutostart.Visibility = "Visible"
        $sync.btnAutostartToggle.Text = $sync.ArrowDown
    } else {
        $sync.pnlAutostart.Visibility = "Collapsed"
        $sync.btnAutostartToggle.Text = $sync.ArrowRight
    }
})
# Parent checkbox enables/disables sub-options
$sync.chkOneDrive.Add_Click({
    $sync.pnlAutostart.IsEnabled = [bool]$sync.chkOneDrive.IsChecked
})

# Worker script
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
        Write-UILog "Auto-restart registered (Task Scheduler)"
    }

    function Remove-AutoRunTask {
        schtasks.exe /delete /tn $sync.TaskName /f 2>$null | Out-Console
        Write-UILog "Auto-restart removed"
        $counterFile = Join-Path $sync.ScriptDir "setup_run.tmp"
        if (Test-Path $counterFile) { Remove-Item $counterFile -Force }
        # Delete setup folder on next login (RunOnce)
        $cleanCmd = "cmd /c rmdir /s /q `"$($sync.ScriptDir)`""
        reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "SmartbarCleanup" /t REG_SZ /d $cleanCmd /f | Out-Console
    }

    try {
        $totalSteps = 0
        if ($sync.DoWifi)      { $totalSteps++ }
        if ($sync.DoEnergy)    { $totalSteps++ }
        if ($sync.DoCalman)    { $totalSteps++ }
        if ($sync.DoUninstall) { $totalSteps++ }
        if ($sync.DoOneDrive)  { $totalSteps++ }
        if ($sync.DoTweaks)    { $totalSteps++ }
        if ($sync.DoUpdates)   { $totalSteps++ }
        if ($totalSteps -eq 0) { $totalSteps = 1 }
        $doneSteps       = 0
        $errCount        = 0
        $okCount         = 0
        $failedStepNames = [System.Collections.Generic.List[string]]::new()

        Write-UILog "=== Run $($sync.RunCount) on $env:COMPUTERNAME ==="
        Write-UILog "Device: $($sync.DeviceModel)  |  SN: $($sync.DeviceSN)"

        # Wi-Fi
        if ($sync.DoWifi) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Connecting to Wi-Fi..." "Step $($doneSteps+1)/$totalSteps"
            Write-UILog "Connecting to Wi-Fi $($sync.WlanSSID)..."
            try {
                # Get-NetConnectionProfile is locale-independent and more reliable
                # than netsh text parsing (no BSSID/encoding issue)
                $alreadyConn = $false
                try {
                    $alreadyConn = (Get-NetConnectionProfile -ErrorAction Stop).Name -contains $sync.WlanSSID
                } catch {
                    # Fallback: netsh line by line (prevents BSSID substring match)
                    foreach ($line in @(netsh wlan show interfaces)) {
                        if ($line -match "^\s+SSID\s+:\s+(.+)$" -and $line -notmatch "BSSID") {
                            $alreadyConn = ($matches[1].Trim() -eq $sync.WlanSSID)
                            break
                        }
                    }
                }
                if ($alreadyConn) {
                    Write-UILog "Wi-Fi $($sync.WlanSSID) already connected" "OK"
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

                    # netsh wlan connect fails elevated (WlanGetAvailableNetworkList Error 5)
                    # Instead: briefly disable adapter -> WLAN AutoConfig connects automatically
                    $wlanName = $null
                    foreach ($line in (netsh wlan show interfaces 2>$null)) {
                        if ($line -match "^\s+Name\s+:\s+(.+)") { $wlanName = $matches[1].Trim(); break }
                    }
                    if ($wlanName) {
                        Write-UILog "Restarting adapter '$wlanName'..."
                        netsh interface set interface "$wlanName" disabled 2>$null | Out-Console
                        Start-Sleep 2
                        netsh interface set interface "$wlanName" enabled  2>$null | Out-Console
                        Start-Sleep 3
                    }

                    Write-UILog "Waiting for Wi-Fi connection..."
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
                        Write-UILog "Wi-Fi $($sync.WlanSSID) connected (after $waited sec)" "OK"
                        $okCount++
                    } else {
                        Write-UILog "Wi-Fi: Timeout after $maxWait sec - connection not confirmed" "WARN"
                        $okCount++
                    }
                }
            } catch {
                Write-UILog "Error Wi-Fi: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Wi-Fi")
            }
            $doneSteps++
        }

        # Power settings
        if ($sync.DoEnergy) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Power settings..." "Step $($doneSteps+1)/$totalSteps"
            Write-UILog "Setting power options..."
            $stepStart = Get-Date
            try {
                powercfg /change monitor-timeout-ac 60 | Out-Console
                powercfg /change monitor-timeout-dc 60 | Out-Console
                powercfg /change standby-timeout-ac 60 | Out-Console
                powercfg /change standby-timeout-dc 60 | Out-Console
                powercfg /change disk-timeout-ac    0  | Out-Console
                powercfg /change disk-timeout-dc    0  | Out-Console
                Write-UILog "Power settings configured ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                $okCount++
            } catch {
                Write-UILog "Error power settings: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Power settings")
            }
            $doneSteps++
        }

        # Install programs
        if ($sync.DoCalman) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Installing programs..." "Step $($doneSteps+1)/$totalSteps"
            Write-UILog "Installing programs..."
            $stepStart = Get-Date
            $progFiles = if (Test-Path $sync.ProgramsDir) {
                Get-ChildItem $sync.ProgramsDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in @(".msi", ".exe") } |
                    Sort-Object Name
            } else { @() }
            $progCount = ($progFiles | Measure-Object).Count
            if ($progCount -eq 0) {
                Write-UILog "No programs in Programs folder" "OK"
                $okCount++
            } else {
                $pi = 0
                foreach ($prog in $progFiles) {
                    $pi++
                    Write-UILog "  ($pi/$progCount) $($prog.Name)"
                    Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Installing $($prog.BaseName)..." "Step $($doneSteps+1)/$totalSteps"
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
                            Set-UIProgress $pct "Installing $($prog.BaseName)... ($($elapsed)s)" "Step $($doneSteps+1)/$totalSteps"
                        }
                        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                            Write-UILog "  $($prog.BaseName) installed ($($elapsed)s)" "OK"
                            $okCount++
                        } else {
                            Write-UILog "  $($prog.BaseName) exit code: $($proc.ExitCode)" "ERROR"
                            $errCount++
                            $failedStepNames.Add("Program: $($prog.BaseName)")
                        }
                    } catch {
                        Write-UILog "  Error $($prog.BaseName): $_" "ERROR"
                        $errCount++
                        $failedStepNames.Add("Program: $($prog.BaseName)")
                    }
                }
                Write-UILog "Programs done ($([int]((Get-Date)-$stepStart).TotalSeconds)s)"
            }
            $doneSteps++
        }

        # Uninstall apps
        if ($sync.DoUninstall) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Uninstalling apps..." "Step $($doneSteps+1)/$totalSteps"
            Write-UILog "Uninstalling apps..."
            $stepStart = Get-Date
            try {
                foreach ($app in $sync.UninstallEntries) {
                    switch ($app.Type) {

                        "OneDrive" {
                            taskkill.exe /f /im OneDrive.exe 2>$null | Out-Console
                            $odu = if (Test-Path "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe") {
                                "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe"
                            } else { "$env:SYSTEMROOT\System32\OneDriveSetup.exe" }
                            if (Test-Path $odu) {
                                $p = Start-Process $odu -ArgumentList "/uninstall" -PassThru -Wait
                                Write-UILog "  OneDrive uninstalled (Exit $($p.ExitCode))" "OK"
                            } else {
                                Write-UILog "  OneDrive not found" "WARN"
                            }
                        }

                        "Appx" {
                            $pattern = $app.Match
                            $removed = 0
                            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                                Where-Object { $_.PackageName -like $pattern } |
                                ForEach-Object {
                                    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
                                    $removed++
                                }
                            Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue |
                                ForEach-Object {
                                    Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                                    $removed++
                                }
                            if ($removed -gt 0) {
                                Write-UILog "  $($app.ID): $removed package(s) removed" "OK"
                            } else {
                                Write-UILog "  $($app.ID): not installed" "OK"
                            }
                        }

                        "Registry" {
                            $uninstKeys = @(
                                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                            )
                            $found = $false
                            foreach ($key in $uninstKeys) {
                                Get-ItemProperty $key -ErrorAction SilentlyContinue |
                                    Where-Object { $_.DisplayName -match $app.Match } |
                                    ForEach-Object {
                                        $found = $true
                                        $uStr = if ($_.QuietUninstallString) { $_.QuietUninstallString } else { $_.UninstallString }
                                        Write-UILog "  Uninstalling $($_.DisplayName)..."
                                        if ($uStr -match "MsiExec") {
                                            $guid = [regex]::Match($uStr, '\{[^}]+\}').Value
                                            Start-Process msiexec.exe -ArgumentList "/x $guid /quiet /norestart" -Wait -ErrorAction SilentlyContinue
                                        } else {
                                            $exe  = [regex]::Match($uStr, '"([^"]+)"').Groups[1].Value
                                            $args = $uStr -replace '"[^"]*"','' -replace '^\s*',''
                                            if (-not $exe) { $exe = $uStr.Split(' ')[0] }
                                            Start-Process $exe -ArgumentList "$args /quiet /silent /S /norestart" -Wait -ErrorAction SilentlyContinue
                                        }
                                        Write-UILog "  $($_.DisplayName) uninstalled" "OK"
                                    }
                            }
                            if (-not $found) { Write-UILog "  $($app.ID): not found" "OK" }
                        }
                    }
                }
                Write-UILog "Apps uninstalled ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                $okCount++
            } catch {
                Write-UILog "Error uninstalling apps: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Uninstall apps")
            }
            $doneSteps++
        }

        # Clean up autostart
        if ($sync.DoOneDrive) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Cleaning up autostart..." "Step $($doneSteps+1)/$totalSteps"
            Write-UILog "Cleaning up autostart..."
            $stepStart = Get-Date
            try {
                $runKey  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
                $runKeyL = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"

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
                                Write-UILog "  $($entry.ID): $key removed from autostart"
                            }
                        }
                    }
                    if ($entry.Tasks) {
                        foreach ($task in $entry.Tasks) {
                            schtasks.exe /change /tn $task /disable 2>$null | Out-Console
                        }
                    }
                }

                Write-UILog "Autostart cleaned up ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                $okCount++
            } catch {
                Write-UILog "Error autostart: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Clean up autostart")
            }
            $doneSteps++
        }

        # Optimize Windows
        if ($sync.DoTweaks) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Optimizing Windows..." "Step $($doneSteps+1)/$totalSteps"
            Write-UILog "Optimizing Windows settings..."
            $stepStart = Get-Date
            try {
                # Disable Sticky Keys
                $stickyPath = "HKCU:\Control Panel\Accessibility\StickyKeys"
                $togglePath = "HKCU:\Control Panel\Accessibility\ToggleKeys"
                $filterPath = "HKCU:\Control Panel\Accessibility\Keyboard Response"
                if (-not (Test-Path $stickyPath)) { New-Item $stickyPath -Force | Out-Console }
                if (-not (Test-Path $togglePath)) { New-Item $togglePath -Force | Out-Console }
                if (-not (Test-Path $filterPath)) { New-Item $filterPath -Force | Out-Console }
                Set-ItemProperty $stickyPath -Name "Flags" -Value "506"  -Force
                Set-ItemProperty $togglePath -Name "Flags" -Value "58"   -Force
                Set-ItemProperty $filterPath -Name "Flags" -Value "122"  -Force
                Write-UILog "  Sticky Keys disabled"

                # Widgets (Windows 11 taskbar)
                $advPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Set-ItemProperty $advPath -Name "TaskbarDa" -Value 0 -Force -ErrorAction SilentlyContinue
                # News and Interests (Windows 10)
                $feedsPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds"
                if (-not (Test-Path $feedsPath)) { New-Item $feedsPath -Force | Out-Console }
                Set-ItemProperty $feedsPath -Name "ShellFeedsTaskbarViewMode" -Value 2 -Force -ErrorAction SilentlyContinue
                Write-UILog "  Widgets/News disabled"

                # Telemetry to minimum
                $telPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                if (-not (Test-Path $telPath)) { New-Item $telPath -Force | Out-Console }
                Set-ItemProperty $telPath -Name "AllowTelemetry" -Value 1 -Force
                $telPath2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
                if (-not (Test-Path $telPath2)) { New-Item $telPath2 -Force | Out-Console }
                Set-ItemProperty $telPath2 -Name "AllowTelemetry" -Value 1 -Force
                Write-UILog "  Telemetry set to minimum"

                # High performance power plan
                # GUID 8c5e7fda = High performance; e9a42b02 = Ultimate performance (desktop only)
                $perfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
                powercfg /setactive $perfGuid 2>$null | Out-Console
                if ($LASTEXITCODE -ne 0) {
                    # Plan not found -> duplicate
                    powercfg /duplicatescheme $perfGuid 2>$null | Out-Console
                    powercfg /setactive $perfGuid 2>$null | Out-Console
                }
                Write-UILog "  High performance activated"

                # Disable Edge First-Run wizard
                $edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
                if (-not (Test-Path $edgePol)) { New-Item $edgePol -Force | Out-Console }
                Set-ItemProperty $edgePol -Name "HideFirstRunExperience" -Value 1 -Type DWord -Force
                Set-ItemProperty $edgePol -Name "StartupBoostEnabled"    -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Write-UILog "  Edge first-run disabled"

                # Set timezone & region
                Set-TimeZone $sync.RegionTimeZone -ErrorAction SilentlyContinue
                Set-WinHomeLocation -GeoId $sync.RegionGeoId -ErrorAction SilentlyContinue
                Set-WinSystemLocale -SystemLocale $sync.RegionLocale -ErrorAction SilentlyContinue
                Set-Culture $sync.RegionLocale -ErrorAction SilentlyContinue
                Write-UILog "  Timezone & region: $($sync.RegionLocale) ($($sync.RegionTimeZone))"

                Write-UILog "Windows optimized ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                $okCount++
            } catch {
                Write-UILog "Error Windows optimization: $_" "ERROR"
                $errCount++
                $failedStepNames.Add("Optimize Windows")
            }
            $doneSteps++
        }

        # Windows Updates
        $updatesInstalled = $false
        if ($sync.DoUpdates) {
            Set-UIProgress ([int]($doneSteps / $totalSteps * 100)) "Windows Updates..." "Step $($doneSteps+1)/$totalSteps"

            # Internet check
            Write-UILog "Checking internet connection..."
            try {
                $null = [System.Net.WebClient]::new().DownloadString("http://www.msftconnecttest.com/connecttest.txt")
                Write-UILog "Internet connection OK" "OK"
            } catch {
                Write-UILog "NO INTERNET - Windows Updates cannot be installed!" "ERROR"
                Write-UILog "Please connect a network cable or Wi-Fi and try again." "ERROR"
                $sync.Window.Dispatcher.Invoke([action]{
                    $sync.btnStart.Content      = "Try again"
                    $sync.btnStart.IsEnabled    = $true
                    $sync.chkWifi.IsEnabled     = $true
                    $sync.chkEnergy.IsEnabled   = $true
                    $sync.chkCalman.IsEnabled   = $true
                    $sync.chkOneDrive.IsEnabled = $true
                    $sync.chkTweaks.IsEnabled   = $true
                    $sync.chkUpdates.IsEnabled  = $true
                    $sync.txtStatus.Text        = "No internet!"
                }, "Normal")
                return
            }

            Write-UILog "Checking PSWindowsUpdate..."
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                try {
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Console
                    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber | Out-Console
                    # Refresh module path so Get-Module finds the new module immediately
                    $userModPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell\Modules"
                    if ($env:PSModulePath -notmatch [regex]::Escape($userModPath)) {
                        $env:PSModulePath = $userModPath + ";" + $env:PSModulePath
                    }
                    Write-UILog "PSWindowsUpdate installed" "OK"
                } catch {
                    Write-UILog "Error PSWindowsUpdate: $_" "ERROR"
                }
            }
            if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
                Import-Module PSWindowsUpdate
                # Trigger Windows Update service before scanning so retry/pending updates
                # are flushed back into the cache (important after a restart)
                Write-UILog "Refreshing Windows Update service..."
                try {
                    Start-Service wuauserv -ErrorAction SilentlyContinue
                    UsoClient.exe StartScan 2>$null
                    Start-Sleep 15
                } catch {}
                Write-UILog "Searching for updates (this may take a few minutes)..."
                $stepStart = Get-Date

                # Run scan in a separate runspace with timeout to prevent infinite hang
                $scanSync = [hashtable]::Synchronized(@{ Done = $false; Result = $null; Error = $null })
                $scanRs   = [runspacefactory]::CreateRunspace()
                $scanRs.ApartmentState = "STA"
                $scanRs.Open()
                $scanRs.SessionStateProxy.SetVariable("sc", $scanSync)
                $scanPs = [powershell]::Create()
                $scanPs.Runspace = $scanRs
                [void]$scanPs.AddScript({
                    try {
                        Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
                        $sc.Result = @(Get-WindowsUpdate -AcceptAll -IgnoreReboot -MicrosoftUpdate -ErrorAction SilentlyContinue)
                    } catch { $sc.Error = $_.ToString() }
                    $sc.Done = $true
                })
                [void]$scanPs.BeginInvoke()

                $scanMax  = 1200   # 20 min timeout for scan
                $scanElap = 0
                while (-not $scanSync.Done -and $scanElap -lt $scanMax) {
                    Start-Sleep 3; $scanElap += 3
                    $pct = [Math]::Min([int]($doneSteps / $totalSteps * 100) + 2, 99)
                    Set-UIProgress $pct "Searching for updates... ($scanElap s)" "Step $($doneSteps+1)/$totalSteps"
                }
                try { $scanPs.Stop() } catch {}
                try { $scanPs.Dispose(); $scanRs.Close(); $scanRs.Dispose() } catch {}

                if (-not $scanSync.Done) {
                    Write-UILog "Update scan timeout after $($scanMax/60) min" "WARN"
                }
                if ($scanSync.Error) {
                    Write-UILog "Scan error: $($scanSync.Error)" "ERROR"
                }

                try {
                    $skipPat  = $sync.UpdateSkipPattern
                    $allFound = if ($scanSync.Result) { @($scanSync.Result) } else { @() }
                    $skipped  = @($allFound | Where-Object { $_.Title -match $skipPat })
                    $updates  = @($allFound | Where-Object { $_.Title -notmatch $skipPat })

                    if ($skipped.Count -gt 0) {
                        Write-UILog "$($skipped.Count) update(s) skipped (will be applied on restart):"
                        foreach ($s in $skipped) { Write-UILog "  [skip] $($s.Title)" }
                    }

                    $count   = $updates.Count
                    if ($count -gt 0) {
                        Write-UILog "$count update(s) found:"
                        $stepBase = [int]($doneSteps / $totalSteps * 100)
                        $stepSize = [int](1 / $totalSteps * 100)
                        $i = 0
                        foreach ($u in $updates) {
                            $i++
                            Write-UILog "  ($i/$count): $($u.Title)"
                        }

                        # KB IDs of filtered updates for Install-WU
                        $filteredKBs = @($updates | ForEach-Object {
                            if ($_.KBArticleIDs) { $_.KBArticleIDs } elseif ($_.KBArticleID) { $_.KBArticleID }
                        } | Where-Object { $_ } | Select-Object -Unique)

                        Write-UILog "Installing $count update(s)..."
                        Set-UIProgress $stepBase "Downloading..." "Step $($doneSteps+1)/$totalSteps"
                        $downloaded = 0
                        $installed  = 0
                        $barWidth   = 24

                        # Installation in a separate runspace with timeout
                        # BIOS/Firmware already filtered out - remaining updates get 15 min
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
                                    Install-WindowsUpdate -KBArticleID $kbs -AcceptAll -IgnoreReboot -MicrosoftUpdate -Confirm:$false |
                                        ForEach-Object { $q.Enqueue($_) }
                                } else {
                                    Install-WindowsUpdate -AcceptAll -IgnoreReboot -MicrosoftUpdate -Confirm:$false -NotTitle $skip |
                                        ForEach-Object { $q.Enqueue($_) }
                                }
                            } catch {
                                $inst.Error = $_.ToString()
                            }
                            $inst.Done = $true
                        })
                        [void]$instPs.BeginInvoke()

                        $instMax  = 900   # 15 min timeout (e.g. large .NET updates)
                        $instElap = 0
                        $qItem    = $null

                        while (-not $instSync.Done -and $instElap -lt $instMax) {
                            Start-Sleep 2; $instElap += 2
                            $gotItem = $false
                            while ($instQueue.TryDequeue([ref]$qItem)) {
                                $gotItem   = $true
                                $statusStr = "$($qItem.Status)"
                                if ($statusStr -match '[DI]') {
                                    try { [Console]::WriteLine("  [$statusStr] $($qItem.Title)") } catch {}
                                }
                                if ($statusStr -match 'Downloaded' -or ($statusStr -match 'D' -and $statusStr -notmatch 'Install')) {
                                    $downloaded++
                                    $filled = [Math]::Min([int]($downloaded / $count * $barWidth), $barWidth)
                                    $bar    = ('#' * $filled) + ('-' * ($barWidth - $filled))
                                    $pct    = $stepBase + [int]([Math]::Min($downloaded, $count) / $count * $stepSize * 0.5)
                                    $uTitle = if ($qItem.Title.Length -gt 35) { $qItem.Title.Substring(0,35) + "..." } else { $qItem.Title }
                                    Write-UILog "  [DL $bar] $([Math]::Min($downloaded,$count))/$count  $uTitle"
                                    Set-UIProgress $pct "Downloading $([Math]::Min($downloaded,$count))/$count..." "Step $($doneSteps+1)/$totalSteps"
                                } elseif ($statusStr -match 'Install') {
                                    $installed++
                                    $filled = [Math]::Min([int]($installed / $count * $barWidth), $barWidth)
                                    $bar    = ('#' * $filled) + ('-' * ($barWidth - $filled))
                                    try { [Console]::WriteLine("  [$bar] $([Math]::Min($installed,$count))/$count") } catch {}
                                    $pct    = $stepBase + [int]($stepSize * 0.5 + [Math]::Min($installed,$count) / $count * $stepSize * 0.5)
                                    $uTitle = if ($qItem.Title.Length -gt 35) { $qItem.Title.Substring(0,35) + "..." } else { $qItem.Title }
                                    Write-UILog "  [IN $bar] $([Math]::Min($installed,$count))/$count  $uTitle"
                                    Set-UIProgress $pct "Installing $([Math]::Min($installed,$count))/$count..." "Step $($doneSteps+1)/$totalSteps"
                                }
                            }
                            # Fallback display only when no new item arrived (e.g. stuck download)
                            if (-not $gotItem) {
                                $dispPct = [Math]::Min($stepBase + [int]($instElap / $instMax * $stepSize), 99)
                                Set-UIProgress $dispPct "Updates running... ($instElap s)" "Step $($doneSteps+1)/$totalSteps"
                            }
                        }

                        # Drain queue
                        while ($instQueue.TryDequeue([ref]$qItem)) {
                            $statusStr = "$($qItem.Status)"
                            if ($statusStr -match 'Install') { $installed++ }
                            if ($statusStr -match 'Downloaded' -or ($statusStr -match 'D' -and $statusStr -notmatch 'Install')) { $downloaded++ }
                        }

                        try { $instPs.Stop() } catch {}
                        try { $instPs.Dispose(); $instRs.Close(); $instRs.Dispose() } catch {}

                        if (-not $instSync.Done) {
                            Write-UILog "Update timeout after $($instMax / 60) min - update stuck (restart will still be scheduled)" "WARN"
                        }
                        if ($instSync.Error) {
                            Write-UILog "Install error: $($instSync.Error)" "ERROR"
                        }
                        Write-UILog "$count update(s) processed ($([int]((Get-Date)-$stepStart).TotalSeconds)s)" "OK"
                        # Sync Windows Update Settings app so it shows correct state
                        try { UsoClient.exe RefreshSettings 2>$null } catch {}
                        $updatesInstalled = $true
                        $okCount++
                    }
                    # No updates found: restart still pending or updates via WUA?
                    if (-not $updatesInstalled) {
                        # 1) Check reboot status
                        try {
                            if (Get-WURebootStatus -Silent -ErrorAction SilentlyContinue) {
                                Write-UILog "Restart pending (updates waiting to be installed)" "OK"
                                $updatesInstalled = $true
                            }
                        } catch {}

                        # 2) Query Windows Update COM API directly - finds retry/stuck updates
                        #    that PSWindowsUpdate sometimes misses
                        if (-not $updatesInstalled) {
                            try {
                                $wuSession  = New-Object -ComObject Microsoft.Update.Session
                                $wuSearcher = $wuSession.CreateUpdateSearcher()
                                $wuResult   = $wuSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
                                $wuCount    = $wuResult.Updates.Count
                                if ($wuCount -gt 0) {
                                    Write-UILog "$wuCount update(s) found via Windows Update API - restarting for next attempt" "OK"
                                    foreach ($u in $wuResult.Updates) { Write-UILog "  [WUA] $($u.Title)" }
                                    $updatesInstalled = $true
                                }
                            } catch {
                                Write-UILog "WUA check error: $_" "WARN"
                            }
                        }

                        if (-not $updatesInstalled) {
                            Write-UILog "No pending updates" "OK"
                        }
                        $okCount++
                    }
                } catch {
                    Write-UILog "Error updates: $_" "ERROR"
                    $errCount++
                    $failedStepNames.Add("Windows Updates")
                    # In AutoRun mode restart anyway - error may be transient,
                    # and updates may have been (partially) installed already
                    if ($sync.AutoRun) { $updatesInstalled = $true }
                }
            } else {
                Write-UILog "PSWindowsUpdate not available" "ERROR"
                $errCount++
                $failedStepNames.Add("Windows Updates")
            }
            $doneSteps++
        }

        Set-UIProgress 100 "Done" ""

        # Restart decision:
        # - Updates installed              -> always restart
        # - First run (no AutoRun)         -> safety restart even without updates
        # - AutoRun pass, no more updates  -> done
        $doRestart = $updatesInstalled -or (-not $sync.AutoRun)

        if ($doRestart) {
            if ($updatesInstalled) {
                Write-UILog "Updates installed - registering auto-restart..."
            } else {
                Write-UILog "First run complete - safety restart + update scan..." "OK"
            }
            Register-AutoRunTask
            Write-UILog "Restarting in 15 seconds..." "OK"

            for ($i = 15; $i -ge 1; $i--) {
                $ii = $i
                $sync.Window.Dispatcher.Invoke([action]{
                    $sync.txtFooter.Text   = "Restarting in $ii seconds..."
                    $sync.btnStart.Content = "Restart now"
                    $sync.btnStart.IsEnabled = $true
                }, "Normal")
                Start-Sleep -Seconds 1
            }
            shutdown.exe /r /t 0

        } else {
            # AutoRun pass, no more updates -> done!
            Remove-AutoRunTask
            Write-UILog "=== Laptop ready! ===" "OK"

            $runCount   = $sync.RunCount
            $logFile    = $sync.LogFile
            $winColor   = if ($errCount -gt 0) { "#2e1a1a" } else { "#1a2e1a" }
            $checkColor = if ($errCount -gt 0) { "#f38ba8" } else { "#a6e3a1" }

            if ($errCount -gt 0) {
                $uniqueFailed = ($failedStepNames | Select-Object -Unique)
                $failedLines  = ($uniqueFailed | ForEach-Object { "  - $_" }) -join "`n"
                $summaryLine  = "$okCount OK  |  $errCount error(s):`n$failedLines"
            } else {
                $summaryLine  = "All $okCount steps successful"
            }
            $detailsText = "$summaryLine`n`n$runCount run(s)`nLog: $logFile"

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
            $sync.txtStatus.Text  = "Error - see log"
            $sync.btnStart.IsEnabled = $true
        }, "Normal")
    }
}

# Button: Start setup / Restart now
$sync.btnStart.Add_Click({
    if ($sync.btnStart.Content -eq "Restart now") {
        shutdown.exe /r /t 0
        return
    }

    $sync.txtFooter.Text = ""

    $sync.DoWifi          = [bool]$sync.chkWifi.IsChecked
    $sync.DoEnergy        = [bool]$sync.chkEnergy.IsChecked
    $sync.DoCalman        = [bool]$sync.chkCalman.IsChecked
    $sync.DoUninstall     = [bool]$sync.chkUninstall.IsChecked
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
    $sync.chkUninstall.IsEnabled = $false
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

# Done view: open log
$sync.btnDoneOpenLog.Add_Click({
    if (Test-Path $sync.LogFile) {
        Start-Process notepad.exe $sync.LogFile
    }
})

# Done view: close button
$sync.btnDoneClose.Add_Click({
    $sync.Window.Close()
})

# AutoRun: start immediately
if ($sync.AutoRun) {
    $sync.btnStart.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
}

if ($sync.CopiedFromUsb) {
    $sync.txtLog.Text = "[OK] Files copied to C:\ProgramData\SmartbarSetup`n[>>] USB drive can now be removed`n`n"
    $sync.txtFooter.Text = "USB drive can be removed"
}

$sync.Window.ShowDialog() | Out-Null
