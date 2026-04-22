#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function OK($msg)        { Write-Host "    OK: $msg" -ForegroundColor Green }
function Warn($msg)      { Write-Host "    !!: $msg" -ForegroundColor Yellow }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " H20 Windows Setup" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# ─── 1. Wacht op internet ─────────────────────────────────────────────────────
Step "1/5" "Wachten op internetverbinding..."
$tries = 0
while (-not (Test-Connection 8.8.8.8 -Count 1 -Quiet) -and $tries -lt 30) {
    Write-Host "    Geen internet, wachten..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    $tries++
}
if ($tries -ge 30) { Write-Host "FOUT: Geen internet na 2.5 min. Sluit af." -ForegroundColor Red; exit 1 }
OK "Internetverbinding actief"

# ─── 2. Privacy: blokkeer bedrijfskoppeling ───────────────────────────────────
Step "2/5" "Privacy: bedrijfskoppeling en telemetry blokkeren"

$msAcc = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount"
New-Item $msAcc -Force | Out-Null
Set-ItemProperty $msAcc "DisableUserAuth" 1 -Type DWord

Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    "NoConnectedUser" 3 -Type DWord -Force

$mdm = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
New-Item $mdm -Force | Out-Null
Set-ItemProperty $mdm "DisableRegistration" 1 -Type DWord

$wpj = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
New-Item $wpj -Force | Out-Null
Set-ItemProperty $wpj "autoWorkplaceJoin" 0 -Type DWord

$cdj = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\CloudDomainJoin"
New-Item $cdj -Force | Out-Null
Set-ItemProperty $cdj "DisableCloudDomainJoin" 1 -Type DWord

Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Stop-Service "dmwappushservice" -Force -ErrorAction SilentlyContinue
Set-Service  "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue

$dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
New-Item $dc -Force | Out-Null
Set-ItemProperty $dc "AllowTelemetry" 0 -Type DWord

$adv = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
New-Item $adv -Force | Out-Null
Set-ItemProperty $adv "Enabled" 0 -Type DWord

$sys = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
New-Item $sys -Force | Out-Null
Set-ItemProperty $sys "EnableActivityFeed"    0 -Type DWord
Set-ItemProperty $sys "PublishUserActivities" 0 -Type DWord
Set-ItemProperty $sys "UploadUserActivities"  0 -Type DWord

Stop-Service "DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service  "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

$cortana = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
New-Item $cortana -Force | Out-Null
Set-ItemProperty $cortana "AllowCortana" 0 -Type DWord

OK "Privacy instellingen geconfigureerd"

# ─── 3. Chocolatey installeren ────────────────────────────────────────────────
Step "3/5" "Chocolatey installeren"
$chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
if (!(Test-Path $chocoExe)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}
if (Test-Path $chocoExe) { OK "Chocolatey gereed" } else { Warn "Chocolatey installatie mislukt - directe download als fallback" }

# ─── 4. Apps installeren ──────────────────────────────────────────────────────
Step "4/5" "Apps installeren"

$tmp = "$env:TEMP\h20"
New-Item $tmp -ItemType Directory -Force | Out-Null

function InstallChoco([string]$name, [string]$pkg) {
    Write-Host "    $name..." -NoNewline
    & $chocoExe install $pkg -y --no-progress --force 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " mislukt" -ForegroundColor Yellow }
}

function InstallDirect([string]$name, [string]$url, [string]$installArgs) {
    Write-Host "    $name..." -NoNewline
    $ext  = if ($url -match "\.msi") { "msi" } else { "exe" }
    $file = "$tmp\$([System.IO.Path]::GetRandomFileName()).$ext"
    try {
        (New-Object System.Net.WebClient).DownloadFile($url, $file)
        if ($ext -eq "msi") { Start-Process msiexec -ArgumentList "/i `"$file`" $installArgs" -Wait -NoNewWindow }
        else                { Start-Process $file -ArgumentList $installArgs -Wait -NoNewWindow }
        Write-Host " OK" -ForegroundColor Green
    } catch { Write-Host " mislukt: $_" -ForegroundColor Yellow }
}

if (Test-Path $chocoExe) {
    InstallChoco "Steam"               "steam"
    InstallChoco "Epic Games Launcher" "epicgameslauncher"
    InstallChoco "NVIDIA App"          "nvidia-app"
} else {
    InstallDirect "Steam"               "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe" "/S"
    InstallDirect "Epic Games Launcher" "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi" "/qn /norestart"
    try {
        $nvPage = (New-Object System.Net.WebClient).DownloadString('https://www.nvidia.com/en-us/software/nvidia-app/')
        if ($nvPage -match 'https://us\.download\.nvidia\.com/nvapp/client/[\d\.]+/NVIDIA_app_v[\d\.]+\.exe') {
            InstallDirect "NVIDIA App" $Matches[0] "-s"
        } else { Warn "NVIDIA App URL niet gevonden" }
    } catch { Warn "NVIDIA App ophalen mislukt" }
}

# Valorant bootstrapper: niet wachten, hij downloadt zelf verder op de achtergrond
Write-Host "    Riot Client / Valorant..." -NoNewline
$valFile = "$tmp\valorant_setup.exe"
try {
    (New-Object System.Net.WebClient).DownloadFile(
        "https://valorant.secure.dyn.riotcdn.net/channels/public/x/installer/current/live.exe",
        $valFile)
    Start-Process $valFile -NoNewWindow
    Write-Host " gestart (installeert op achtergrond)" -ForegroundColor Green
} catch { Write-Host " mislukt: $_" -ForegroundColor Yellow }

# ─── 5. Windows activeren ─────────────────────────────────────────────────────
Step "5/5" "Windows activeren"
slmgr /ato
OK "Activatie aangevraagd"

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Setup voltooid!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("NVIDIA, Steam, Epic Games en Valorant zijn geinstalleerd.", "H20 Setup klaar!") | Out-Null
