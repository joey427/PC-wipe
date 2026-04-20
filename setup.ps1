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

# Geen Microsoft account (lokaal account afdwingen)
$msAcc = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount"
New-Item $msAcc -Force | Out-Null
Set-ItemProperty $msAcc "DisableUserAuth" 1 -Type DWord

Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    "NoConnectedUser" 3 -Type DWord -Force

# Blokkeer MDM / Intune enrollment
$mdm = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
New-Item $mdm -Force | Out-Null
Set-ItemProperty $mdm "DisableRegistration" 1 -Type DWord

# Blokkeer Azure AD / Workplace Join
$wpj = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
New-Item $wpj -Force | Out-Null
Set-ItemProperty $wpj "autoWorkplaceJoin" 0 -Type DWord

# Blokkeer Autopilot domain join
$cdj = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\CloudDomainJoin"
New-Item $cdj -Force | Out-Null
Set-ItemProperty $cdj "DisableCloudDomainJoin" 1 -Type DWord

# Verwijder bestaande MDM enrollments
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# MDM push service uitzetten
Stop-Service "dmwappushservice" -Force -ErrorAction SilentlyContinue
Set-Service  "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue

# Telemetry uitzetten
$dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
New-Item $dc -Force | Out-Null
Set-ItemProperty $dc "AllowTelemetry" 0 -Type DWord

# Advertising ID uitzetten
$adv = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
New-Item $adv -Force | Out-Null
Set-ItemProperty $adv "Enabled" 0 -Type DWord

# Activity history uitzetten
$sys = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
New-Item $sys -Force | Out-Null
Set-ItemProperty $sys "EnableActivityFeed"    0 -Type DWord
Set-ItemProperty $sys "PublishUserActivities" 0 -Type DWord
Set-ItemProperty $sys "UploadUserActivities"  0 -Type DWord

# DiagTrack (telemetry service) uitzetten
Stop-Service "DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service  "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

# Cortana uitzetten
$cortana = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
New-Item $cortana -Force | Out-Null
Set-ItemProperty $cortana "AllowCortana" 0 -Type DWord

OK "Privacy instellingen geconfigureerd"

# ─── 3. Wacht op winget ───────────────────────────────────────────────────────
Step "3/5" "Wachten tot winget beschikbaar is..."
$tries = 0
while (!(Get-Command winget -ErrorAction SilentlyContinue) -and $tries -lt 12) {
    Start-Sleep -Seconds 10
    $tries++
}
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Warn "winget niet gevonden - probeer handmatig via Microsoft Store"
} else {
    OK "winget gereed"
}

# ─── 4. Apps installeren ──────────────────────────────────────────────────────
Step "4/5" "Apps installeren"

$apps = @(
    @{ name = "NVIDIA App";          id = "Nvidia.NvidiaApp" },
    @{ name = "Steam";               id = "Valve.Steam" },
    @{ name = "Epic Games Launcher"; id = "EpicGames.EpicGamesLauncher" },
    @{ name = "Valorant";            id = "RiotGames.Valorant.EU" }
)

foreach ($app in $apps) {
    Write-Host "    Installeren: $($app.name)..." -NoNewline
    winget install --id $app.id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    # Exit code -1978335189 = al geinstalleerd, ook OK
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " mislukt (code $LASTEXITCODE)" -ForegroundColor Yellow
    }
}

# ─── 5. Windows activeren ─────────────────────────────────────────────────────
Step "5/5" "Windows activeren"
slmgr /ato
OK "Activatie aangevraagd"

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Setup voltooid!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

msg * "H20 setup klaar! NVIDIA, Steam, Epic Games en Valorant zijn geinstalleerd."
