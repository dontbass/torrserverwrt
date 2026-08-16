# TorrServer Installer for Windows
# Compatible with PowerShell 5.1+ (built-in on Windows 10/11)
# Usage: run install.bat OR powershell -ExecutionPolicy Bypass -File install.ps1

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

$InstallDir  = "C:\TorrServer"
$ServicePort = 8090
$ServiceName = "TorrServer"
$TaskName    = "TorrServer"
$BinName     = "TorrServer-windows-amd64.exe"
$BinPath     = Join-Path $InstallDir $BinName
$VersionFile = Join-Path $InstallDir "version"
$AccsFile    = Join-Path $InstallDir "accs.db"
$LogFile     = Join-Path $InstallDir "torrserver.log"

# Action from command line argument
$Action = ""
if ($args.Count -gt 0) { $Action = $args[0].ToLower() }

# ============================================================
# OUTPUT
# ============================================================

function Write-Color {
    param([string]$Text, [string]$Color = "White")
    $map = @{
        "red"="Red"; "green"="Green"; "yellow"="Yellow"
        "cyan"="Cyan"; "blue"="Blue"; "white"="White"
    }
    $fc = if ($map.ContainsKey($Color)) { $map[$Color] } else { "White" }
    Write-Host $Text -ForegroundColor $fc
}

function Write-Ok   { param([string]$Msg) Write-Color " [OK]  $Msg" "green"  }
function Write-Warn { param([string]$Msg) Write-Color " [!!]  $Msg" "yellow" }
function Write-Err  { param([string]$Msg) Write-Color " [ERR] $Msg" "red"    }
function Write-Info { param([string]$Msg) Write-Color " [*]   $Msg" "cyan"   }
function Write-Sep  { Write-Color "=============================================================" "blue" }

function Show-Logo {
    Write-Host ""
    Write-Color "  TTTTTTT  OOO  RRRR  RRRR " "red"
    Write-Color "    TTT   O   O R   R R   R" "red"
    Write-Color "    TTT   O   O RRRR  RRRR " "red"
    Write-Color "    TTT   O   O R  R  R  R " "red"
    Write-Color "    TTT    OOO  R   R R   R" "red"
    Write-Color "  SSSSS EEEEE RRRR  V   V EEEEE RRRR " "blue"
    Write-Color "  S     E     R   R V   V E     R   R" "blue"
    Write-Color "  SSSSS EEEE  RRRR   V V  EEEE  RRRR " "blue"
    Write-Color "      S E     R  R    V   E     R  R " "blue"
    Write-Color "  SSSSS EEEEE R   R   V   EEEEE R   R" "blue"
    Write-Color "                        for Windows" "white"
    Write-Host ""
}

# ============================================================
# HELPERS
# ============================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]$id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestRelease {
    try {
        $r = Invoke-RestMethod "https://api.github.com/repos/YouROK/TorrServer/releases/latest" `
             -Headers @{ "User-Agent" = "torrserverwrt" }
        return $r.tag_name
    } catch { return $null }
}

function Get-InstalledVersion {
    if (Test-Path $VersionFile) {
        return (Get-Content $VersionFile -Raw).Trim()
    }
    return "unknown"
}

function Test-Installed { return (Test-Path $BinPath) }

function Test-Running {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { return $true }
    $proc = Get-Process -Name ($BinName -replace "\.exe$","") -ErrorAction SilentlyContinue
    return ($null -ne $proc)
}

function Get-ServicePort {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $task.Actions[0].Arguments -match "--port (\d+)") { return $Matches[1] }
    $svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName -match "--port (\d+)") { return $Matches[1] }
    return "8090"
}

function Get-LocalIP {
    try {
        $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notmatch "^127\." -and $_.PrefixOrigin -ne "WellKnown" }
        if ($addrs) { return ($addrs | Select-Object -First 1).IPAddress }
    } catch {}
    return "localhost"
}

function Get-DiskFreeGB {
    try {
        $drive = Split-Path -Qualifier $InstallDir
        $d = Get-PSDrive -Name ($drive -replace ":","") -ErrorAction SilentlyContinue
        if ($d) { return [math]::Round($d.Free / 1GB, 1) }
    } catch {}
    return 999
}

function Test-AuthEnabled {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $task.Actions[0].Arguments -match "--httpauth") { return $true }
    $svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName -match "--httpauth") { return $true }
    return $false
}

function Get-AuthCredentials {
    if (-not (Test-Path $AccsFile)) { return $null }
    try {
        $json = Get-Content $AccsFile -Raw | ConvertFrom-Json
        $prop = $json.PSObject.Properties | Select-Object -First 1
        if ($prop) { return @{ Login = $prop.Name; Password = $prop.Value } }
    } catch {}
    return $null
}

# ============================================================
# SERVICE MANAGEMENT
# ============================================================

function Register-AsTask {
    param([string]$Arguments)
    Write-Info "Registering as Scheduled Task (runs as SYSTEM, starts with Windows)..."
    $action    = New-ScheduledTaskAction -Execute $BinPath -Argument $Arguments
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $settings  = New-ScheduledTaskSettingsSet `
                    -RestartCount 3 `
                    -RestartInterval (New-TimeSpan -Minutes 1) `
                    -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
    Register-ScheduledTask -TaskName $TaskName -Action $action `
        -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

function Start-Torr {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue; return }
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) { Start-Service $ServiceName -ErrorAction SilentlyContinue; return }
}

function Stop-Torr {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) { Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue }
    Get-Process -Name ($BinName -replace "\.exe$","") -ErrorAction SilentlyContinue | Stop-Process -Force
}

function Remove-Torr {
    Stop-Torr
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd) { & nssm.exe remove $ServiceName confirm 2>$null | Out-Null }
    Remove-NetFirewallRule -DisplayName "TorrServer" -ErrorAction SilentlyContinue
}

function Add-FWRule {
    param([int]$RulePort)
    New-NetFirewallRule -DisplayName "TorrServer" `
        -Direction Inbound -Protocol TCP -LocalPort $RulePort `
        -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Info "Firewall rule added for port $RulePort"
}

# ============================================================
# DOWNLOAD
# ============================================================

function Download-TorrServer {
    param([string]$Version)
    $url     = "https://github.com/YouROK/TorrServer/releases/download/$Version/$BinName"
    $tmpPath = Join-Path $InstallDir "$BinName.tmp"

    $freeGB = Get-DiskFreeGB
    $needGB = if (Test-Path $BinPath) { 0.15 } else { 0.08 }
    if ($freeGB -lt $needGB) {
        Write-Warn "Low disk space: $freeGB GB free"
        if (Test-Path $BinPath) {
            $ans = Read-Host " Remove old binary to free space? (Y/N)"
            if ($ans -match "^[Yy]") {
                Remove-Item $BinPath -Force
                Write-Info "Old binary removed"
            } else {
                Write-Err "Aborted: not enough space"
                return $false
            }
        } else {
            Write-Err "Not enough disk space"
            return $false
        }
    }

    Write-Info "Downloading TorrServer $Version..."
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $tmpPath)
    } catch {
        Write-Err "Download failed: $_"
        if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force }
        return $false
    }

    $size = (Get-Item $tmpPath).Length
    if ($size -lt 1MB) {
        Write-Err "Downloaded file too small ($size bytes)"
        Remove-Item $tmpPath -Force
        return $false
    }

    Move-Item -Path $tmpPath -Destination $BinPath -Force
    Set-Content -Path $VersionFile -Value $Version -Encoding UTF8
    Write-Ok "Downloaded TorrServer $Version"
    return $true
}

# ============================================================
# ACTIONS
# ============================================================

function Install-TorrServer {
    Write-Host ""
    Write-Sep
    Write-Color " TorrServer Installation" "cyan"
    Write-Sep
    Write-Host ""
    Write-Warn "REQUIREMENTS:"
    Write-Host "  RAM:   256 MB min, 512 MB+ recommended"
    Write-Host "  Space: ~80 MB"
    Write-Host "  OS:    Windows 10/11 or Windows Server 2016+"
    Write-Host ""

    if (Test-Installed) {
        $cur = Get-InstalledVersion
        Write-Warn "Already installed (version: $cur)"
        $ans = Read-Host " Update to latest? (Y/N)"
        if ($ans -match "^[Yy]") { Update-TorrServer }
        return
    }

    $ans = Read-Host " Proceed with installation? (Y/N)"
    if ($ans -notmatch "^[Yy]") { Write-Host " Cancelled"; return }

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    Write-Info "Fetching latest version..."
    $latest = Get-LatestRelease
    if (-not $latest) { Write-Err "Could not get version from GitHub"; return }
    Write-Info "Latest version: $latest"

    if (-not (Download-TorrServer $latest)) { return }

    # Port
    $p = Read-Host " Port (press Enter for default 8090)"
    if ($p -match "^\d+$" -and [int]$p -ge 1024 -and [int]$p -le 65535) {
        $ServicePort = [int]$p
    }

    # Auth
    $authArgs = "--port $ServicePort --path `"$InstallDir`""
    $authUser = ""; $authPass = ""
    $ans = Read-Host " Enable HTTP authorization? (Y/N)"
    if ($ans -match "^[Yy]") {
        $authUser = Read-Host " Username"
        $authPass = Read-Host " Password"
        $json = "{`n  `"$authUser`": `"$authPass`"`n}"
        Set-Content -Path $AccsFile -Value $json -Encoding UTF8
        $authArgs += " --httpauth"
        Write-Ok "Credentials saved"
    }

    Register-AsTask -Arguments $authArgs

    # Firewall
    $ans = Read-Host " Add firewall rule for port $ServicePort? (Y/N)"
    if ($ans -match "^[Yy]") { Add-FWRule -RulePort $ServicePort }

    Start-Sleep -Seconds 2
    $ip = Get-LocalIP

    Write-Host ""
    Write-Sep
    if (Test-Running) {
        Write-Ok "TorrServer $latest installed and RUNNING"
    } else {
        Write-Warn "Installed but did not start. Check log: $LogFile"
    }
    Write-Sep
    Write-Color " Web UI:  http://${ip}:${ServicePort}" "cyan"
    if ($authUser) { Write-Host " Login:   $authUser   Password: $authPass" }
    Write-Host " Log:     $LogFile"
    Write-Host ""
}

function Update-TorrServer {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }
    Write-Info "Fetching latest version..."
    $latest = Get-LatestRelease
    if (-not $latest) { Write-Err "Could not get version"; return }
    $cur = Get-InstalledVersion
    Write-Host " Installed: $cur  |  Latest: $latest"
    if ($cur -eq $latest) { Write-Ok "Already up to date"; return }
    Write-Info "Stopping service..."
    Stop-Torr
    Start-Sleep -Seconds 2
    if (-not (Download-TorrServer $latest)) {
        Write-Warn "Download failed, restarting old version..."
        Start-Torr; return
    }
    Start-Torr
    Start-Sleep -Seconds 2
    if (Test-Running) { Write-Ok "Updated to $latest" }
    else { Write-Warn "Updated but did not start. Check: $LogFile" }
}

function Show-Status {
    Write-Host ""
    Write-Sep
    Write-Color " TorrServer Status" "cyan"
    Write-Sep
    if (-not (Test-Installed)) {
        Write-Color " State:    NOT INSTALLED" "red"
        Write-Sep; Write-Host ""; return
    }
    $ver  = Get-InstalledVersion
    $port = Get-ServicePort
    $ip   = Get-LocalIP
    Write-Host " Version:  $ver"
    Write-Host " Binary:   $BinName"
    if (Test-Running) {
        Write-Color " Service:  RUNNING" "green"
        Write-Color " Address:  http://${ip}:${port}" "green"
    } else {
        Write-Color " Service:  STOPPED" "red"
        Write-Host " Address:  http://${ip}:${port}"
    }
    if (Test-AuthEnabled) {
        $creds = Get-AuthCredentials
        Write-Color " Auth:     ON" "yellow"
        if ($creds) {
            Write-Host " Login:    $($creds.Login)"
            Write-Host " Password: $($creds.Password)"
        }
    } else {
        Write-Color " Auth:     OFF" "cyan"
    }
    $updTask = Get-ScheduledTask -TaskName "TorrServerUpdate" -ErrorAction SilentlyContinue
    if ($updTask) { Write-Color " Auto-upd: ON" "green" }
    else          { Write-Color " Auto-upd: OFF" "cyan" }
    Write-Host " Update:   " -NoNewline
    $latest = Get-LatestRelease
    if ($latest -and $latest -ne $ver) { Write-Color "available $latest" "yellow" }
    elseif ($latest)                   { Write-Color "not required" "green" }
    else                               { Write-Host "could not check" }
    Write-Sep; Write-Host ""
}

function Remove-TorrServer {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }
    Write-Host ""
    Write-Host " Directory: $InstallDir"
    Write-Host " Version:   $(Get-InstalledVersion)"
    Write-Host ""
    Write-Color " WARNING: All data will be deleted!" "red"
    $ans = Read-Host " Are you sure? (Y/N)"
    if ($ans -notmatch "^[Yy]") { Write-Host " Cancelled"; return }
    Remove-Torr
    Unregister-ScheduledTask -TaskName "TorrServerUpdate" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "TorrServer removed"
    Write-Host ""
}

function Set-AutoUpdate {
    $updTask = Get-ScheduledTask -TaskName "TorrServerUpdate" -ErrorAction SilentlyContinue
    if ($updTask) {
        Write-Host " Auto-update already configured (weekly, Sunday 04:00)"
        $ans = Read-Host " Disable? (Y/N)"
        if ($ans -match "^[Yy]") {
            Unregister-ScheduledTask -TaskName "TorrServerUpdate" -Confirm:$false
            Write-Ok "Auto-update disabled"
        }
        return
    }
    Write-Host ""
    Write-Host " Auto-update: weekly check (Sunday 04:00), downloads only if new version available"
    Write-Host " Log: $InstallDir\update.log"
    $ans = Read-Host " Enable? (Y/N)"
    if ($ans -notmatch "^[Yy]") { Write-Host " Cancelled"; return }
    $scriptPath = $MyInvocation.ScriptName
    if (-not $scriptPath) { $scriptPath = "$InstallDir\install.ps1" }
    $argStr  = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" update"
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argStr
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "04:00"
    $settings= New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    $princ   = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
    Register-ScheduledTask -TaskName "TorrServerUpdate" -Action $action `
        -Trigger $trigger -Settings $settings -Principal $princ -Force | Out-Null
    Write-Ok "Auto-update enabled (Sunday 04:00)"
}

# ============================================================
# ENTRY POINT
# ============================================================

if (-not (Test-Admin)) {
    Write-Color " [ERR] Run as Administrator!" "red"
    Write-Host " Use install.bat (it handles this automatically)"
    Read-Host " Press Enter to exit"
    exit 1
}

switch ($Action) {
    "install" { Install-TorrServer }
    "update"  { Update-TorrServer  }
    "status"  { Show-Status        }
    "remove"  { Remove-TorrServer  }
    default   {
        Show-Logo
        if (Test-Installed) {
            Write-Host " Version: $(Get-InstalledVersion)"
            if (Test-Running) { Write-Color " Service: RUNNING" "green" }
            else              { Write-Color " Service: STOPPED" "red"   }
        }
        Write-Host ""
        Write-Color "  [i] install / update" "green"
        Write-Color "  [s] status"           "cyan"
        Write-Color "  [c] auto-update"      "cyan"
        Write-Color "  [d] remove"           "red"
        Write-Color "  [q] quit"             "yellow"
        Write-Host ""
        $running = $true
        while ($running) {
            $choice = Read-Host " Choice"
            switch ($choice.ToLower()) {
                "i" { Install-TorrServer; $running = $false }
                "s" { Show-Status }
                "c" { Set-AutoUpdate }
                "d" { Remove-TorrServer; $running = $false }
                "q" { $running = $false }
                default { Write-Host " Enter i, s, c, d or q" }
            }
        }
    }
}
