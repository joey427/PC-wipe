#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"
$ProgressPreference   = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
function Download($url, $out) {
    (New-Object System.Net.WebClient).DownloadFile($url, $out)
}

Write-Host "`n============================================" -ForegroundColor Red
Write-Host " H20 NUKE - Cleanup + Herinstallatie" -ForegroundColor Red
Write-Host "============================================`n" -ForegroundColor Red

# ─── 1. Processen stoppen ─────────────────────────────────────────────────────
Step "1/5" "Launcher processen stoppen"

@("steam","steamwebhelper","steamservice","EpicGamesLauncher","EpicWebHelper",
  "RiotClientServices","RiotClientUx","RiotClientUxRender","VALORANT",
  "Battle.net","Agent","EADesktop","EABackgroundService","Origin",
  "NvBackend","nvsphelper64","NVDisplay.Container") | ForEach-Object {
    Get-Process -Name $_ -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill(); OK "Gestopt: $($_.Name)"
    }
}
Start-Sleep -Seconds 3

# ─── 2. Mappen en registry verwijderen ────────────────────────────────────────
Step "2/5" "Bestanden en registry opruimen"

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
Stop-Service "dmwappushservice","DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service  "dmwappushservice","DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 -Type DWord
OK "Privacy ingesteld"

# ─── 4. Chocolatey installeren ────────────────────────────────────────────────
Step "4/5" "Chocolatey installeren"

if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";C:\ProgramData\chocolatey\bin"
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
    OK "Chocolatey gereed"
} else {
    Warn "Chocolatey installatie mislukt - probeer directe download"
}

# ─── 5. Apps installeren ──────────────────────────────────────────────────────
Step "5/5" "Apps installeren"

$tmp = "$env:TEMP\h20-install"
New-Item $tmp -ItemType Directory -Force | Out-Null

if (Get-Command choco -ErrorAction SilentlyContinue) {
    # Via Chocolatey
    @(
        @{ name = "NVIDIA App";          pkg = "nvidia-display-driver" },
        @{ name = "Steam";               pkg = "steam" },
        @{ name = "Epic Games Launcher"; pkg = "epicgameslauncher" },
        @{ name = "Valorant (Riot)";     pkg = "valorant" }
    ) | ForEach-Object {
        Write-Host "    Installeren: $($_.name)..." -NoNewline
        choco install $_.pkg -y --no-progress 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host " OK" -ForegroundColor Green }
        else { Write-Host " mislukt" -ForegroundColor Yellow }
    }
} else {
    # Directe download als fallback
    Warn "Chocolatey niet beschikbaar - directe download"

    $installers = @(
        @{ name = "Steam";               url = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe";          args = "/S" },
        @{ name = "Epic Games Launcher"; url = "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi"; args = "/qn /norestart" },
        @{ name = "Riot Client";         url = "https://valorant.secure.dyn.riotcdn.net/channels/public/x/installer/current/live.exe"; args = "--skip-to-install" }
    )

    foreach ($app in $installers) {
        Write-Host "    Downloaden: $($app.name)..." -NoNewline
        $ext  = if ($app.url -match "\.msi") { "msi" } else { "exe" }
        $file = "$tmp\$($app.name).$ext"
        try {
            Download $app.url $file
            if ($ext -eq "msi") { Start-Process msiexec -ArgumentList "/i `"$file`" $($app.args)" -Wait }
            else                { Start-Process $file   -ArgumentList $app.args -Wait }
            Write-Host " OK" -ForegroundColor Green
        } catch { Write-Host " mislukt" -ForegroundColor Yellow }
    }
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Klaar! PC is schoon en apps zijn terug." -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green
msg * "H20 Nuke klaar! Steam, Epic, Valorant en NVIDIA herinstalleerd."
