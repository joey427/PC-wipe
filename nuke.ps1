#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"
$ProgressPreference   = "SilentlyContinue"

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function OK($msg)        { Write-Host "    + $msg" -ForegroundColor Green }
function Warn($msg)      { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Del($path) {
    if (Test-Path $path) {
        cmd /c "rd /s /q `"$path`"" 2>$null
        if (!(Test-Path $path)) { OK "Verwijderd: $path" }
        else { Warn "Gedeeltelijk (nog in gebruik): $path" }
    }
}

Write-Host "`n============================================" -ForegroundColor Red
Write-Host " H20 NUKE - Cleanup + Herinstallatie" -ForegroundColor Red
Write-Host "============================================`n" -ForegroundColor Red

# ─── 0. Winget localiseren ────────────────────────────────────────────────────
# Zoek winget op alle bekende locaties
function Find-Winget {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "C:\Users\h20\AppData\Local\Microsoft\WindowsApps\winget.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    $found = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" `
        -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

$winget = Find-Winget

if (!$winget) {
    Warn "winget niet gevonden - bezig met installeren..."
    try {
        $tmp = "$env:TEMP\winget-install"
        New-Item $tmp -ItemType Directory -Force | Out-Null
        Invoke-WebRequest "https://aka.ms/getwinget"                                                                                    -OutFile "$tmp\winget.msixbundle"       -UseBasicParsing
        Invoke-WebRequest "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"                                                    -OutFile "$tmp\vclibs.appx"             -UseBasicParsing
        Invoke-WebRequest "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"    -OutFile "$tmp\xaml.appx"               -UseBasicParsing
        Add-AppxPackage "$tmp\vclibs.appx"   -ErrorAction SilentlyContinue
        Add-AppxPackage "$tmp\xaml.appx"     -ErrorAction SilentlyContinue
        Add-AppxPackage "$tmp\winget.msixbundle"
        Start-Sleep -Seconds 5
        $winget = Find-Winget
    } catch { Warn "winget installatie mislukt: $_" }
}

if ($winget) { OK "winget: $winget" } else { Warn "winget niet beschikbaar - app-installatie wordt overgeslagen" }

# ─── 1. Alle launcher processen stoppen ──────────────────────────────────────
Step "1/6" "Launcher processen stoppen"

@("steam","steamwebhelper","steamservice","EpicGamesLauncher","EpicWebHelper",
  "RiotClientServices","RiotClientUx","RiotClientUxRender","VALORANT",
  "Battle.net","Agent","EADesktop","EABackgroundService","Origin",
  "NvBackend","nvsphelper64","NVDisplay.Container") | ForEach-Object {
    Get-Process -Name $_ -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill(); OK "Gestopt: $_"
    }
}
Start-Sleep -Seconds 3

# ─── 2. Game launchers verwijderen via winget ─────────────────────────────────
Step "2/6" "Game launchers verwijderen (winget)"

if ($winget) {
    @("Valve.Steam","EpicGames.EpicGamesLauncher","RiotGames.Valorant.EU",
      "Blizzard.BattleNet","ElectronicArts.EADesktop","ElectronicArts.Origin",
      "Nvidia.NvidiaApp","Nvidia.GeForceExperience") | ForEach-Object {
        & $winget uninstall --id $_ --silent --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { OK "$_ verwijderd" }
    }
} else { Warn "winget niet beschikbaar, stap overgeslagen" }

# ─── 3. Overgebleven mappen verwijderen ───────────────────────────────────────
Step "3/6" "Overgebleven mappen opruimen"

@(
    "$env:ProgramFiles\Steam",
    "${env:ProgramFiles(x86)}\Steam",
    "$env:ProgramFiles\Epic Games",
    "${env:ProgramFiles(x86)}\Epic Games",
    "$env:ProgramFiles\Riot Games",
    "${env:ProgramFiles(x86)}\Riot Games",
    "${env:ProgramFiles(x86)}\Blizzard Entertainment",
    "$env:ProgramFiles\Electronic Arts",
    "${env:ProgramFiles(x86)}\Origin",
    "$env:ProgramFiles\NVIDIA Corporation\NVIDIA app",
    "$env:LOCALAPPDATA\Steam",
    "$env:LOCALAPPDATA\EpicGamesLauncher",
    "$env:LOCALAPPDATA\Riot Games",
    "$env:APPDATA\Riot Games",
    "$env:PROGRAMDATA\Epic",
    "$env:PROGRAMDATA\Riot Games"
) | ForEach-Object { Del $_ }

# ─── 4. Registry opruimen ─────────────────────────────────────────────────────
Step "4/6" "Registry opruimen"

@("HKCU:\SOFTWARE\Valve","HKCU:\SOFTWARE\Epic Games","HKCU:\SOFTWARE\Riot Games",
  "HKLM:\SOFTWARE\Valve","HKLM:\SOFTWARE\WOW6432Node\Valve",
  "HKLM:\SOFTWARE\Epic Games","HKLM:\SOFTWARE\WOW6432Node\Epic Games",
  "HKLM:\SOFTWARE\Riot Games","HKLM:\SOFTWARE\WOW6432Node\Riot Games",
  "HKLM:\SOFTWARE\WOW6432Node\Origin") | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        OK "Registry: $_"
    }
}

# ─── 5. Privacy + MDM blokkade ────────────────────────────────────────────────
Step "5/6" "Privacy en bedrijfsblokkade instellen"

New-Item "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount" "DisableUserAuth" 1 -Type DWord
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "NoConnectedUser" 3 -Type DWord -Force

New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM" "DisableRegistration" 1 -Type DWord

New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" "autoWorkplaceJoin" 0 -Type DWord

Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Stop-Service "dmwappushservice","DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service  "dmwappushservice","DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 -Type DWord

OK "Privacy ingesteld"

# ─── 6. Apps herinstalleren ───────────────────────────────────────────────────
Step "6/6" "Apps herinstalleren"

if (!$winget) {
    Warn "winget niet gevonden - open Microsoft Store en installeer 'App Installer'"
    Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
    exit
}

@(
    @{ name = "NVIDIA App";          id = "Nvidia.NvidiaApp" },
    @{ name = "Steam";               id = "Valve.Steam" },
    @{ name = "Epic Games Launcher"; id = "EpicGames.EpicGamesLauncher" },
    @{ name = "Valorant";            id = "RiotGames.Valorant.EU" }
) | ForEach-Object {
    Write-Host "    Installeren: $($_.name)..." -NoNewline
    & $winget install --id $_.id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " mislukt (code $LASTEXITCODE)" -ForegroundColor Yellow }
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Klaar! PC is schoon en apps zijn terug." -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green
msg * "H20 Nuke klaar! Steam, Epic, Valorant en NVIDIA herinstalleerd."
