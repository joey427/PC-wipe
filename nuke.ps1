#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"
$ProgressPreference   = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function OK($msg)        { Write-Host "    + $msg" -ForegroundColor Green }
function Warn($msg)      { Write-Host "    ! $msg" -ForegroundColor Yellow }

function NukePath([string]$path) {
    if (Test-Path $path) {
        cmd /c "rd /s /q `"$path`"" 2>$null
        if (!(Test-Path $path)) { OK "Weg: $path" }
        else { Warn "Gedeeltelijk (nog in gebruik): $path" }
    }
}

function StopSvc([string]$name) {
    Stop-Service  -Name $name -Force        -ErrorAction SilentlyContinue
    Set-Service   -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
}

Write-Host "`n============================================" -ForegroundColor Red
Write-Host " H20 NUKE - Alles weg, fresh start" -ForegroundColor Red
Write-Host "============================================`n" -ForegroundColor Red

# ─── 1. Alle services en processen stoppen ───────────────────────────────────
Step "1/7" "Alles stoppen"

foreach ($s in @("NvContainerLocalSystem","NvContainerNetworkService",
    "NVDisplay.ContainerLocalSystem","nvagent","NvTelemetryContainer",
    "Steam Client Service","EpicOnlineServices","dmwappushservice","DiagTrack",
    "Discord Update","DiscordService",
    "RiotClientService","vgc","vgk","RiotClientCrashHandler")) { StopSvc $s }

# Vanguard kernel driver forceren via sc
foreach ($d in @("vgk","vgc")) {
    sc.exe stop $d 2>$null
    sc.exe delete $d 2>$null
}

# Stop alle niet-systeem processen
$systemProcs = @("System","smss","csrss","wininit","winlogon","services","lsass",
    "svchost","dwm","explorer","taskhostw","spoolsv","SearchIndexer","audiodg",
    "fontdrvhost","sihost","ctfmon","powershell","cmd","conhost","lsaiso","Memory Compression")

Get-Process | Where-Object {
    $_.Name -notin $systemProcs -and
    $_.Name -notlike "Microsoft*" -and
    $_.Name -notlike "Windows*" -and
    $_.SessionId -gt 0
} | ForEach-Object {
    $_.Kill()
    OK "Gestopt: $($_.Name)"
}
Start-Sleep -Seconds 4

# ─── 2. Alle Win32 apps verwijderen ──────────────────────────────────────────
Step "2/7" "Alle geinstalleerde apps verwijderen"

# Nooit verwijderen
$skip = @(
    "Microsoft Visual C++","Microsoft .NET",".NET Runtime",".NET Desktop Runtime",
    ".NET Host","DirectX","WebView2","Microsoft Edge","Windows SDK",
    "Windows Update","Security Update","Update for Windows","Hotfix",
    "Windows Defender","NVIDIA Graphics Driver","NVIDIA HD Audio",
    "Intel","AMD","Realtek Audio","Realtek Ethernet","WinRAR","7-Zip",
    "Microsoft Windows Desktop Runtime"
)

$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$apps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and $_.UninstallString -and $_.SystemComponent -ne 1 }

foreach ($app in $apps) {
    $name = $app.DisplayName
    $shouldSkip = $false
    foreach ($s in $skip) {
        if ($name -like "*$s*") { $shouldSkip = $true; break }
    }
    if ($shouldSkip) { continue }

    Write-Host "    Verwijderen: $name..." -NoNewline
    $us = $app.UninstallString

    try {
        if ($us -match "msiexec" -or $us -match "MsiExec") {
            if ($us -match "(\{[A-F0-9\-]+\})" -or $us -match "(\{[a-f0-9\-]+\})") {
                $guid = $Matches[1]
                Start-Process msiexec -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -Wait -NoNewWindow
            }
        } else {
            # Haal exe pad op (met of zonder quotes)
            $exe = if ($us -match '^"([^"]+)"') { $Matches[1] } else { ($us -split " ")[0] }
            $extraArgs = "/S /SILENT /VERYSILENT /UNINSTALL /quiet /norestart /SUPPRESSMSGBOXES"
            if (Test-Path $exe) {
                Start-Process $exe -ArgumentList $extraArgs -Wait -NoNewWindow
            }
        }
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " overgeslagen" -ForegroundColor DarkGray
    }
}

# ─── 3. AppX packages verwijderen (Store apps) ───────────────────────────────
Step "3/7" "Windows Store apps verwijderen"

$keepAppx = @("Microsoft.WindowsStore","Microsoft.Windows.Photos",
    "Microsoft.WindowsCalculator","Microsoft.WindowsNotepad",
    "Microsoft.DesktopAppInstaller","Microsoft.UI.Xaml*",
    "Microsoft.VCLibs*","Microsoft.NET*","Microsoft.WindowsTerminal",
    "MicrosoftWindows.Client*","Microsoft.Windows.StartMenuExperienceHost",
    "Microsoft.Windows.ShellExperienceHost","windows.immersivecontrolpanel",
    "InputApp","LockApp","Microsoft.AAD*","Microsoft.AccountsControl*",
    "Microsoft.BioEnrollment","Microsoft.CredDialogHost","Microsoft.ECApp",
    "Microsoft.LockApp","Microsoft.Win32WebViewHost","Microsoft.Windows.Apprep*",
    "Microsoft.Windows.AssignedAccessLockApp","Microsoft.Windows.CloudExperienceHost",
    "Microsoft.Windows.ContentDeliveryManager","Microsoft.Windows.OOBENetworkCaptivePortal",
    "Microsoft.Windows.OOBENetworkConnectionFlow","Microsoft.Windows.PeopleExperienceHost",
    "Microsoft.Windows.PinningConfirmationDialog","Microsoft.Windows.SecHealthUI",
    "Microsoft.Windows.SecureAssessmentBrowser","Microsoft.XboxGameCallableUI")

Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
    $pkg = $_.Name
    $keep = $false
    foreach ($k in $keepAppx) {
        if ($pkg -like $k) { $keep = $true; break }
    }
    !$keep
} | ForEach-Object {
    Write-Host "    AppX weg: $($_.Name)" -ForegroundColor DarkGray
    Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
}
OK "AppX opgeruimd"

# ─── 4. AppData en overblijfselen opruimen ────────────────────────────────────
Step "4/7" "AppData opruimen"

# Bekende app-mappen in AppData
$appDataFolders = @(
    "$env:LOCALAPPDATA\Discord",
    "$env:APPDATA\Discord",
    "$env:LOCALAPPDATA\Steam",
    "$env:LOCALAPPDATA\EpicGamesLauncher",
    "$env:LOCALAPPDATA\Riot Games",
    "$env:APPDATA\Riot Games",
    "$env:LOCALAPPDATA\Programs\Opera",
    "$env:LOCALAPPDATA\Programs\Opera GX",
    "$env:APPDATA\Opera Software",
    "$env:LOCALAPPDATA\Programs\Spotify",
    "$env:APPDATA\Spotify",
    "$env:LOCALAPPDATA\Telegram Desktop",
    "$env:APPDATA\Telegram Desktop",
    "$env:LOCALAPPDATA\WhatsApp",
    "$env:APPDATA\WhatsApp",
    "$env:PROGRAMDATA\Epic",
    "$env:PROGRAMDATA\Riot Games",
    "$env:PROGRAMDATA\Battle.net",
    "$env:ProgramFiles\Riot Games",
    "${env:ProgramFiles(x86)}\Steam",
    "${env:ProgramFiles(x86)}\Epic Games",
    "$env:ProgramFiles\Epic Games",
    "$env:ProgramFiles\NVIDIA Corporation\NVIDIA app"
)
foreach ($f in $appDataFolders) { NukePath $f }

# Temp files
foreach ($t in @($env:TEMP, $env:TMP, "C:\Windows\Temp")) {
    Get-ChildItem $t -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
OK "AppData schoon"

# ─── 5. Desktop en startmenu ─────────────────────────────────────────────────
Step "5/7" "Desktop en startmenu leegmaken"

foreach ($desktop in @("$env:PUBLIC\Desktop","$env:USERPROFILE\Desktop")) {
    Get-ChildItem $desktop -Include "*.lnk","*.url" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

foreach ($sm in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")) {
    Get-ChildItem $sm -Recurse -Include "*.lnk" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "*Windows*" -and $_.FullName -notlike "*Microsoft*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
OK "Desktop en startmenu schoon"

# ─── 6. Privacy + MDM blokkade ────────────────────────────────────────────────
Step "6/7" "Privacy en bedrijfsblokkade instellen"

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

# ─── 7. Apps herinstalleren ───────────────────────────────────────────────────
Step "7/7" "Apps installeren"

$chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
if (!(Test-Path $chocoExe)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

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
    # NVIDIA App: dynamisch laatste versie ophalen
    try {
        $nvPage = (New-Object System.Net.WebClient).DownloadString('https://www.nvidia.com/en-us/software/nvidia-app/')
        if ($nvPage -match 'https://us\.download\.nvidia\.com/nvapp/client/[\d\.]+/NVIDIA_app_v[\d\.]+\.exe') {
            InstallDirect "NVIDIA App" $Matches[0] "-s"
        } else { Warn "NVIDIA App URL niet gevonden" }
    } catch { Warn "NVIDIA App ophalen mislukt" }
}

# Valorant: via Shell.Application zodat hij in user-context draait (niet als SYSTEM)
Write-Host "    Riot Client / Valorant..." -NoNewline
$valFile = "$env:PUBLIC\valorant_setup.exe"
try {
    (New-Object System.Net.WebClient).DownloadFile(
        "https://valorant.secure.dyn.riotcdn.net/channels/public/x/installer/current/live.exe",
        $valFile)
    $shell = New-Object -ComObject Shell.Application
    $shell.ShellExecute($valFile, "", "", "open", 1)
    Write-Host " gestart (installeert op achtergrond)" -ForegroundColor Green
} catch { Write-Host " mislukt: $_" -ForegroundColor Yellow }

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " Klaar! PC is clean, apps zijn terug." -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("Steam, Epic, Valorant en NVIDIA herinstalleerd.", "H20 Nuke klaar!") | Out-Null
