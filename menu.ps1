#Requires -RunAsAdministrator
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# ── Kleuren ───────────────────────────────────────────────────────────────────
$Bg     = [Drawing.Color]::FromArgb(15, 15, 15)
$Card   = [Drawing.Color]::FromArgb(26, 26, 26)
$Accent = [Drawing.Color]::FromArgb(220, 38, 38)
$White  = [Drawing.Color]::White
$Gray   = [Drawing.Color]::FromArgb(120, 120, 120)
$Green  = [Drawing.Color]::FromArgb(34, 197, 94)
$Orange = [Drawing.Color]::FromArgb(249, 115, 22)

# ── App catalogus ─────────────────────────────────────────────────────────────
$catalog = @(
    [pscustomobject]@{ Cat="GAME LAUNCHERS"; Name="Steam";                  Pkg="steam";             Special="" },
    [pscustomobject]@{ Cat="GAME LAUNCHERS"; Name="Epic Games Launcher";    Pkg="epicgameslauncher"; Special="" },
    [pscustomobject]@{ Cat="GAME LAUNCHERS"; Name="Valorant / Riot Client"; Pkg="";                  Special="valorant" },
    [pscustomobject]@{ Cat="GAME LAUNCHERS"; Name="Battle.net";             Pkg="battle.net";        Special="" },
    [pscustomobject]@{ Cat="GAME LAUNCHERS"; Name="EA App";                 Pkg="ea-app";            Special="" },
    [pscustomobject]@{ Cat="GAME LAUNCHERS"; Name="Ubisoft Connect";        Pkg="ubisoft-connect";   Special="" },
    [pscustomobject]@{ Cat="GAME LAUNCHERS"; Name="GOG Galaxy";             Pkg="goggalaxy";         Special="" },
    [pscustomobject]@{ Cat="GAMES";          Name="Minecraft";              Pkg="minecraft-launcher";Special="" },
    [pscustomobject]@{ Cat="GAMES";          Name="Roblox";                 Pkg="roblox";            Special="" },
    [pscustomobject]@{ Cat="BROWSERS";       Name="Google Chrome";          Pkg="googlechrome";      Special="" },
    [pscustomobject]@{ Cat="BROWSERS";       Name="Mozilla Firefox";        Pkg="firefox";           Special="" },
    [pscustomobject]@{ Cat="BROWSERS";       Name="Brave";                  Pkg="brave";             Special="" },
    [pscustomobject]@{ Cat="BROWSERS";       Name="Opera GX";               Pkg="opera-gx";          Special="" },
    [pscustomobject]@{ Cat="BROWSERS";       Name="Opera";                  Pkg="opera";             Special="" },
    [pscustomobject]@{ Cat="BROWSERS";       Name="Vivaldi";                Pkg="vivaldi";           Special="" }
)

# ── Venster ───────────────────────────────────────────────────────────────────
$form                  = New-Object Windows.Forms.Form
$form.Text             = "H20 Install Center"
$form.ClientSize       = New-Object Drawing.Size(720, 540)
$form.StartPosition    = "CenterScreen"
$form.BackColor        = $Bg
$form.FormBorderStyle  = "FixedSingle"
$form.MaximizeBox      = $false
$form.Font             = New-Object Drawing.Font("Segoe UI", 9)

# ── Header ────────────────────────────────────────────────────────────────────
$hdr            = New-Object Windows.Forms.Panel
$hdr.Dock       = "Top"
$hdr.Height     = 62
$hdr.BackColor  = $Card
$form.Controls.Add($hdr)

$lH20           = New-Object Windows.Forms.Label
$lH20.Text      = "H20"
$lH20.Font      = New-Object Drawing.Font("Segoe UI", 22, [Drawing.FontStyle]::Bold)
$lH20.ForeColor = $Accent
$lH20.Location  = New-Object Drawing.Point(20, 10)
$lH20.AutoSize  = $true
$hdr.Controls.Add($lH20)

$lTitle           = New-Object Windows.Forms.Label
$lTitle.Text      = "Install Center"
$lTitle.Font      = New-Object Drawing.Font("Segoe UI", 14)
$lTitle.ForeColor = $White
$lTitle.Location  = New-Object Drawing.Point(96, 18)
$lTitle.AutoSize  = $true
$hdr.Controls.Add($lTitle)

# ── Checkboxes opbouwen ───────────────────────────────────────────────────────
$checks = @{}

function Add-Section([string]$title, $items, [int]$x, [int]$y) {
    $lbl           = New-Object Windows.Forms.Label
    $lbl.Text      = $title
    $lbl.Font      = New-Object Drawing.Font("Segoe UI", 8, [Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $Accent
    $lbl.Location  = New-Object Drawing.Point($x, $y)
    $lbl.AutoSize  = $true
    $form.Controls.Add($lbl)
    $y += 22
    foreach ($app in $items) {
        $cb           = New-Object Windows.Forms.CheckBox
        $cb.Text      = $app.Name
        $cb.ForeColor = $White
        $cb.BackColor = $Bg
        $cb.Location  = New-Object Drawing.Point($x, $y)
        $cb.AutoSize  = $true
        $cb.Tag       = $app
        $form.Controls.Add($cb)
        $script:checks[$app.Name] = $cb
        $y += 26
    }
    return $y
}

$launchers = @($catalog | Where-Object { $_.Cat -eq "GAME LAUNCHERS" })
$browsers  = @($catalog | Where-Object { $_.Cat -eq "BROWSERS" })
$games     = @($catalog | Where-Object { $_.Cat -eq "GAMES" })

Add-Section "GAME LAUNCHERS" $launchers 30  82 | Out-Null
$afterBrowsers = Add-Section "BROWSERS" $browsers 390 82
Add-Section "GAMES" $games 390 ($afterBrowsers + 10) | Out-Null

# ── Log output ────────────────────────────────────────────────────────────────
$rtb             = New-Object Windows.Forms.RichTextBox
$rtb.Location    = New-Object Drawing.Point(20, 370)
$rtb.Size        = New-Object Drawing.Size(680, 100)
$rtb.BackColor   = [Drawing.Color]::FromArgb(10, 10, 10)
$rtb.ForeColor   = $Gray
$rtb.Font        = New-Object Drawing.Font("Consolas", 8)
$rtb.ReadOnly    = $true
$rtb.BorderStyle = "None"
$rtb.Text        = "Selecteer apps en klik op Installeren."
$form.Controls.Add($rtb)

function Log($msg, $clr = $null) {
    if (-not $clr) { $clr = $Gray }
    $rtb.SelectionStart  = $rtb.TextLength
    $rtb.SelectionLength = 0
    $rtb.SelectionColor  = $clr
    $rtb.AppendText("`n$msg")
    $rtb.ScrollToCaret()
    [Windows.Forms.Application]::DoEvents()
}

# ── Knoppen ───────────────────────────────────────────────────────────────────
$btnAll                              = New-Object Windows.Forms.Button
$btnAll.Text                         = "Alles selecteren"
$btnAll.Location                     = New-Object Drawing.Point(20, 482)
$btnAll.Size                         = New-Object Drawing.Size(150, 34)
$btnAll.BackColor                    = [Drawing.Color]::FromArgb(40, 40, 40)
$btnAll.ForeColor                    = $White
$btnAll.FlatStyle                    = "Flat"
$btnAll.FlatAppearance.BorderColor   = [Drawing.Color]::FromArgb(60, 60, 60)
$form.Controls.Add($btnAll)

$btnGo                             = New-Object Windows.Forms.Button
$btnGo.Text                        = "Installeren"
$btnGo.Location                    = New-Object Drawing.Point(550, 482)
$btnGo.Size                        = New-Object Drawing.Size(150, 34)
$btnGo.BackColor                   = $Accent
$btnGo.ForeColor                   = $White
$btnGo.FlatStyle                   = "Flat"
$btnGo.FlatAppearance.BorderColor  = $Accent
$btnGo.Font                        = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($btnGo)

$btnAll.Add_Click({
    $any = ($script:checks.Values | Where-Object { $_.Checked }).Count -gt 0
    $script:checks.Values | ForEach-Object { $_.Checked = -not $any }
    $btnAll.Text = if ($any) { "Alles selecteren" } else { "Niets selecteren" }
})

# ── Install logica ────────────────────────────────────────────────────────────
$chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"

$btnGo.Add_Click({
    $sel = @($script:checks.Values | Where-Object { $_.Checked })
    if ($sel.Count -eq 0) { Log "Niets geselecteerd." $Orange; return }

    $btnGo.Enabled = $false
    $btnGo.Text    = "Bezig..."

    if (!(Test-Path $chocoExe)) {
        Log "Chocolatey installeren..." $White
        Set-ExecutionPolicy Bypass -Scope Process -Force
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }

    foreach ($cb in $sel) {
        $app = $cb.Tag

        if ($app.Special -eq "valorant") {
            Log "Valorant downloaden (72MB)..." $White
            $vf = "$env:PUBLIC\Install_Valorant.exe"
            try {
                (New-Object System.Net.WebClient).DownloadFile(
                    "https://raw.githubusercontent.com/joey427/PC-wipe/main/Install_Valorant.exe", $vf)
                $usr = (Get-CimInstance Win32_ComputerSystem).UserName
                if ($usr) {
                    $act = New-ScheduledTaskAction -Execute $vf
                    $tri = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
                    $pri = New-ScheduledTaskPrincipal -UserId $usr -LogonType Interactive -RunLevel Limited
                    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
                    Register-ScheduledTask -TaskName "H20-Valorant" -Action $act -Trigger $tri -Principal $pri -Settings $set -Force | Out-Null
                    Log "+ Valorant gestart als $usr" $Green
                } else {
                    Copy-Item $vf "$env:PUBLIC\Desktop\Install_Valorant.exe" -Force
                    Log "! Valorant: dubbelklik op bureaublad" $Orange
                }
            } catch { Log "! Valorant mislukt: $_" $Orange }
            continue
        }

        Log "$($app.Name) installeren..." $White
        & $chocoExe install $app.Pkg -y --no-progress --force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "+ $($app.Name) OK" $Green }
        else                     { Log "! $($app.Name) mislukt (choco code $LASTEXITCODE)" $Orange }
    }

    $btnGo.Enabled = $true
    $btnGo.Text    = "Installeren"
    Log "Klaar!" $Green
})

[Windows.Forms.Application]::Run($form)
