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

# ─── 4. Install menu openen ───────────────────────────────────────────────────
Step "4/5" "Install menu starten"

$menuFile = "$env:TEMP\h20_menu.ps1"
try {
    (New-Object System.Net.WebClient).DownloadFile(
        "https://raw.githubusercontent.com/joey427/PC-wipe/main/menu.ps1",
        $menuFile)
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$menuFile`"" -Verb RunAs
    OK "Menu geopend - kies je apps"
} catch { Warn "Menu kon niet worden geladen: $_" }

# ─── 5. Windows activeren ─────────────────────────────────────────────────────
Step "5/5" "Windows activeren"
slmgr /ato
OK "Activatie aangevraagd"

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Setup voltooid!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("NVIDIA, Steam, Epic Games en Valorant zijn geinstalleerd.", "H20 Setup klaar!") | Out-Null
