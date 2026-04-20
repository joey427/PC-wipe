#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"
$ProgressPreference   = "SilentlyContinue"

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function OK($msg)        { Write-Host "    + $msg" -ForegroundColor Green }
function Warn($msg)      { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Del($path)      { if (Test-Path $path) { Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue; OK "Verwijderd: $path" } }

Write-Host "`n============================================" -ForegroundColor Red
Write-Host " H20 NUKE - Cleanup + Herinstallatie" -ForegroundColor Red
Write-Host "============================================`n" -ForegroundColor Red

# ─── 1. Game launchers verwijderen via winget ─────────────────────────────────
Step "1/6" "Game launchers verwijderen (winget)"

$remove = @(
    "Valve.Steam",
    "EpicGames.EpicGamesLauncher",
    "RiotGames.Valorant.EU",
    "RiotGames.LeagueOfLegends.EU",
    "Blizzard.BattleNet",
    "ElectronicArts.EADesktop",
    "ElectronicArts.Origin",
    "Ubisoft.Connect",
    "Nvidia.NvidiaApp",
    "Nvidia.GeForceExperience"
)

foreach ($id in $remove) {
    $r = winget uninstall --id $id --silent --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0) { OK "$id verwijderd" }
}

# ─── 2. Overgebleven bestanden en mappen verwijderen ──────────────────────────
Step "2/6" "Overgebleven mappen opruimen"

$folders = @(
    "$env:ProgramFiles\Steam",
    "$env:ProgramFiles (x86)\Steam",
    "$env:ProgramFiles\Epic Games",
    "$env:ProgramFiles (x86)\Epic Games",
    "$env:ProgramFiles\Riot Games",
    "$env:ProgramFiles (x86)\Riot Games",
    "$env:ProgramFiles\Battle.net",
    "$env:ProgramFiles (x86)\Battle.net",
    "$env:ProgramFiles\Blizzard Entertainment",
    "$env:ProgramFiles (x86)\Blizzard Entertainment",
    "$env:ProgramFiles\EA Games",
    "$env:ProgramFiles\Electronic Arts",
    "$env:ProgramFiles (x86)\Origin",
    "$env:ProgramFiles\Ubisoft",
    "$env:ProgramFiles (x86)\Ubisoft",
    "$env:ProgramFiles\NVIDIA Corporation\NVIDIA app",
    "$env:LOCALAPPDATA\Steam",
    "$env:LOCALAPPDATA\EpicGamesLauncher",
    "$env:LOCALAPPDATA\Riot Games",
    "$env:LOCALAPPDATA\Battle.net",
    "$env:LOCALAPPDATA\Origin",
    "$env:APPDATA\Steam",
    "$env:APPDATA\Epic Games",
    "$env:APPDATA\Battle.net",
    "$env:APPDATA\Origin",
    "$env:APPDATA\Riot Games",
    "$env:APPDATA\Ubisoft Game Launcher",
    "$env:PROGRAMDATA\Battle.net",
    "$env:PROGRAMDATA\Epic",
    "$env:PROGRAMDATA\Origin",
    "$env:PROGRAMDATA\Riot Games"
)

foreach ($f in $folders) { Del $f }

# ─── 3. Registry opruimen ─────────────────────────────────────────────────────
Step "3/6" "Registry opruimen"

$regKeys = @(
    "HKCU:\SOFTWARE\Valve",
    "HKCU:\SOFTWARE\Epic Games",
    "HKCU:\SOFTWARE\Riot Games",
    "HKCU:\SOFTWARE\Blizzard Entertainment",
    "HKCU:\SOFTWARE\Electronic Arts",
    "HKCU:\SOFTWARE\Origin",
    "HKCU:\SOFTWARE\Ubisoft",
    "HKLM:\SOFTWARE\Valve",
    "HKLM:\SOFTWARE\WOW6432Node\Valve",
    "HKLM:\SOFTWARE\Epic Games",
    "HKLM:\SOFTWARE\WOW6432Node\Epic Games",
    "HKLM:\SOFTWARE\Riot Games",
    "HKLM:\SOFTWARE\WOW6432Node\Riot Games",
    "HKLM:\SOFTWARE\Blizzard Entertainment",
    "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment",
    "HKLM:\SOFTWARE\Electronic Arts",
    "HKLM:\SOFTWARE\WOW6432Node\Electronic Arts",
    "HKLM:\SOFTWARE\Origin",
    "HKLM:\SOFTWARE\WOW6432Node\Origin"
)

foreach ($key in $regKeys) { Del $key }

# ─── 4. Malware aanpak: startup entries en scheduled tasks ────────────────────
Step "4/6" "Verdachte startup entries en scheduled tasks checken"

$legitimatePublishers = @(
    "Microsoft", "NVIDIA", "Intel", "AMD", "Realtek",
    "Logitech", "Corsair", "SteelSeries", "Razer",
    "ASUS", "MSI", "Gigabyte", "ASRock"
)

# Startup registry keys checken
$runKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

foreach ($key in $runKeys) {
    if (!(Test-Path $key)) { continue }
    $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
    if (!$props) { continue }
    $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
        $name = $_.Name
        $val  = $_.Value
        $trusted = $false
        foreach ($pub in $legitimatePublishers) {
            if ($val -match $pub) { $trusted = $true; break }
        }
        if (-not $trusted) {
            Warn "Verdachte startup entry gevonden: $name = $val"
            Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue
            OK "Verwijderd: $name"
        }
    }
}

# Scheduled tasks checken op verdachte locaties
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskPath -notlike "\Microsoft\*" -and
    $_.TaskPath -ne "\" -and
    $_.State -ne "Disabled"
} | ForEach-Object {
    $trusted = $false
    foreach ($pub in $legitimatePublishers) {
        if ($_.TaskName -match $pub -or $_.TaskPath -match $pub) { $trusted = $true; break }
    }
    if (-not $trusted) {
        Warn "Verdachte scheduled task: $($_.TaskPath)$($_.TaskName)"
        Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
        OK "Uitgeschakeld: $($_.TaskName)"
    }
}

# ─── 5. Temp bestanden en cache opruimen ──────────────────────────────────────
Step "5/6" "Temp bestanden opruimen"

$tempPaths = @(
    $env:TEMP,
    $env:TMP,
    "C:\Windows\Temp",
    "$env:LOCALAPPDATA\Temp",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache*"
)

foreach ($p in $tempPaths) {
    Get-ChildItem -Path $p -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
OK "Temp mappen geleegd"

# Prefetch leegmaken
Get-ChildItem "C:\Windows\Prefetch" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
OK "Prefetch geleegd"

# ─── 6. Privacy + MDM blokkade + apps herinstalleren ─────────────────────────
Step "6/6" "Privacy instellen + apps herinstalleren"

# Geen Microsoft account
$msAcc = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount"
New-Item $msAcc -Force | Out-Null
Set-ItemProperty $msAcc "DisableUserAuth" 1 -Type DWord

Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    "NoConnectedUser" 3 -Type DWord -Force

# MDM / Intune / Azure AD blokkeren
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

# Telemetry uit
$dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
New-Item $dc -Force | Out-Null
Set-ItemProperty $dc "AllowTelemetry" 0 -Type DWord

Stop-Service "DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service  "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

OK "Privacy ingesteld"

# Wacht op winget
$tries = 0
while (!(Get-Command winget -ErrorAction SilentlyContinue) -and $tries -lt 12) {
    Start-Sleep -Seconds 5; $tries++
}

# Apps herinstalleren
$apps = @(
    @{ name = "NVIDIA App";          id = "Nvidia.NvidiaApp" },
    @{ name = "Steam";               id = "Valve.Steam" },
    @{ name = "Epic Games Launcher"; id = "EpicGames.EpicGamesLauncher" },
    @{ name = "Valorant";            id = "RiotGames.Valorant.EU" }
)

foreach ($app in $apps) {
    Write-Host "    Installeren: $($app.name)..." -NoNewline
    winget install --id $app.id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " mislukt (code $LASTEXITCODE)" -ForegroundColor Yellow
    }
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Klaar! PC is schoon en apps zijn terug." -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green

msg * "H20 Nuke klaar! Steam, Epic, Valorant en NVIDIA zijn herinstalleerd."
