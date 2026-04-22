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

# ─── 2. Eerdere policies opruimen (blokkeerden Microsoft account / Minecraft) ──
Step "2/5" "Oude policies verwijderen"

$oldPolicies = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\CloudDomainJoin",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
)
foreach ($p in $oldPolicies) {
    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "NoConnectedUser" -Force -ErrorAction SilentlyContinue

gpupdate /force | Out-Null
OK "Policies verwijderd en cache ververst"

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
