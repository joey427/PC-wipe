#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"
$ProgressPreference   = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function OK($msg)        { Write-Host "    + $msg" -ForegroundColor Green }
function Warn($msg)      { Write-Host "    ! $msg" -ForegroundColor Yellow }

function NukePath($path) {
    if (Test-Path $path) {
        cmd /c "rd /s /q `"$path`"" 2>$null
        if (!(Test-Path $path)) { OK "Weg: $path" }
        else { Warn "Gedeeltelijk (dienst nog actief): $path" }
    }
}

Write-Host "`n============================================" -ForegroundColor Red
Write-Host " H20 NUKE - Cleanup + Herinstallatie" -ForegroundColor Red
Write-Host "============================================`n" -ForegroundColor Red

# ─── 1. Services en processen stoppen ────────────────────────────────────────
Step "1/5" "Services en processen stoppen"

$services = @(
    "NvContainerLocalSystem","NvContainerNetworkService",
    "NVDisplay.ContainerLocalSystem","nvagent","NvTelemetryContainer",
    "NvDisplayContainer","Steam Client Service","EpicOnlineServices",
    "dmwappushservice","DiagTrack"
)
foreach ($s in $services) {
    Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
}

$procs = @("steam","steamwebhelper","steamservice","EpicGamesLauncher",
    "EpicWebHelper","RiotClientServices","RiotClientUx","RiotClientUxRender",
    "VALORANT","Battle.net","Agent","EADesktop","Origin",
    "NvBackend","nvsphelper64","NVDisplay.Container","NVIDIA Share",
    "nvcontainer","nvcplui")
foreach ($p in $procs) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill(); OK "Gestopt: $($_.Name)"
    }
}
Start-Sleep -Seconds 4

# ─── 2. Bestanden opruimen ────────────────────────────────────────────────────
Step "2/5" "Bestanden opruimen"

@(
    "$env:ProgramFiles\Steam",
    "${env:ProgramFiles(x86)}\Steam",
    "$env:ProgramFiles\Epic Games",
    "${env:ProgramFiles(x86)}\Epic Games",
    "$env:ProgramFiles\Riot Games",
    "${env:ProgramFiles(x86)}\Riot Games",
    "${env:ProgramFiles(x86)}\Blizzard Entertainment",
    "$env:ProgramFiles\Electronic Arts",
    "$env:ProgramFiles\NVIDIA Corporation\NVIDIA app",
    "$env:LOCALAPPDATA\Steam",
    "$env:LOCALAPPDATA\EpicGamesLauncher",
    "$env:LOCALAPPDATA\Riot Games",
    "$env:APPDATA\Riot Games",
    "$env:PROGRAMDATA\Epic",
    "$env:PROGRAMDATA\Riot Games"
) | ForEach-Object { NukePath $_ }

@("HKCU:\SOFTWARE\Valve","HKCU:\SOFTWARE\Epic Games","HKCU:\SOFTWARE\Riot Games",
  "HKLM:\SOFTWARE\Valve","HKLM:\SOFTWARE\WOW6432Node\Valve",
  "HKLM:\SOFTWARE\Epic Games","HKLM:\SOFTWARE\WOW6432Node\Epic Games",
  "HKLM:\SOFTWARE\Riot Games","HKLM:\SOFTWARE\WOW6432Node\Riot Games") | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        OK "Registry: $_"
    }
}

# ─── 3. Privacy + MDM blokkade ────────────────────────────────────────────────
Step "3/5" "Privacy en bedrijfsblokkade instellen"

New-Item "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount" "DisableUserAuth" 1 -Type DWord
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "NoConnectedUser" 3 -Type DWord -Force
New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM" "DisableRegistration" 1 -Type DWord
New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" "autoWorkplaceJoin" 0 -Type DWord
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 -Type DWord
OK "Privacy ingesteld"

# ─── 4. Chocolatey installeren ────────────────────────────────────────────────
Step "4/5" "Chocolatey installeren"

$chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
if (!(Test-Path $chocoExe)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}
if (Test-Path $chocoExe) { OK "Chocolatey gereed" }
else { Warn "Chocolatey installatie mislukt" }

# ─── 5. Apps installeren ──────────────────────────────────────────────────────
Step "5/5" "Apps installeren"

$tmp = "$env:TEMP\h20"
New-Item $tmp -ItemType Directory -Force | Out-Null

function Install-Choco($name, $pkg) {
    Write-Host "    $name via Chocolatey..." -NoNewline
    & $chocoExe install $pkg -y --no-progress --force 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " mislukt ($LASTEXITCODE)" -ForegroundColor Yellow }
}

function Install-Direct($name, $url, $args) {
    Write-Host "    $name direct download..." -NoNewline
    $ext  = if ($url -match "\.msi") { "msi" } else { "exe" }
    $file = "$tmp\$(([System.IO.Path]::GetRandomFileName())).$ext"
    try {
        (New-Object System.Net.WebClient).DownloadFile($url, $file)
        if ($ext -eq "msi") { Start-Process msiexec -ArgumentList "/i `"$file`" $args" -Wait -NoNewWindow }
        else                { Start-Process $file -ArgumentList $args -Wait -NoNewWindow }
        Write-Host " OK" -ForegroundColor Green
    } catch { Write-Host " mislukt: $_" -ForegroundColor Yellow }
}

if (Test-Path $chocoExe) {
    Install-Choco "Steam"               "steam"
    Install-Choco "Epic Games Launcher" "epicgameslauncher"
} else {
    Install-Direct "Steam"               "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe" "/S"
    Install-Direct "Epic Games Launcher" "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi" "/qn /norestart"
}

# Riot Client (Valorant) — altijd directe download, niet in Chocolatey
Install-Direct "Riot Client / Valorant" "https://valorant.secure.dyn.riotcdn.net/channels/public/x/installer/current/live.exe" "--skip-to-install"

# NVIDIA App — directe download
Install-Direct "NVIDIA App" "https://us.download.nvidia.com/nvapp/client/11.0.0.385/NVIDIA_app_v11.0.0.385.exe" "-s"

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Klaar! PC is schoon en apps zijn terug." -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green
msg * "H20 Nuke klaar! Steam, Epic, Valorant en NVIDIA herinstalleerd."
