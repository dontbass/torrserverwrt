# TorrServer Installer for Windows
# Works on PowerShell 5.1+ (built-in on Windows 10/11)
# Run via: install.bat  OR  powershell -ExecutionPolicy Bypass -File install.ps1

# Обходим политику выполнения для текущего процесса (не меняет системные настройки)
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
} catch {}

<#
.SYNOPSIS
    TorrServer installer for Windows
.DESCRIPTION
    Downloads and installs TorrServer as a Windows service or scheduled task.
    Supports Windows 10/11 and Windows Server 2016+.
.PARAMETER Port
    Port for TorrServer web interface (default: 8090)
.PARAMETER InstallDir
    Installation directory (default: C:\TorrServer)
.PARAMETER Action
    Action to perform: install, update, status, remove (default: interactive menu)
.PARAMETER NoColor
    Disable colored output
.EXAMPLE
    .\install.ps1
    .\install.ps1 -Action install -Port 8090
    .\install.ps1 -Action update
    .\install.ps1 -Action remove
#>

param(
    [string]$Action    = "",
    [int]   $Port      = 8090,
    [string]$InstallDir = "C:\TorrServer",
    [switch]$NoColor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# ЦВЕТА И ВЫВОД
# ============================================================

function Write-Color {
    param([string]$Text, [string]$Color = "White")
    if ($NoColor) { Write-Host $Text }
    else {
        $map = @{
            red    = "Red"
            green  = "Green"
            yellow = "Yellow"
            cyan   = "Cyan"
            blue   = "Blue"
            white  = "White"
        }
        $fc = if ($map.ContainsKey($Color)) { $map[$Color] } else { "White" }
        Write-Host $Text -ForegroundColor $fc
    }
}

function Write-Ok    { param([string]$Msg) Write-Color " [OK]  $Msg" "green"  }
function Write-Warn  { param([string]$Msg) Write-Color " [!!]  $Msg" "yellow" }
function Write-Err   { param([string]$Msg) Write-Color " [ERR] $Msg" "red"    }
function Write-Info  { param([string]$Msg) Write-Color " [*]   $Msg" "cyan"   }
function Write-Sep   { Write-Color "=============================================================" "blue" }

function Show-Logo {
    Write-Host ""
    Write-Color "  ████████╗ ██████╗ ██████╗ ██████╗ " "red"
    Write-Color "     ██╔══╝██╔═══██╗██╔══██╗██╔══██╗" "red"
    Write-Color "     ██║   ██║   ██║██████╔╝██████╔╝" "red"
    Write-Color "     ██║   ██║   ██║██╔══██╗██╔══██╗" "red"
    Write-Color "     ██║   ╚██████╔╝██║  ██║██║  ██║" "red"
    Write-Color "     ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝" "red"
    Write-Color "  ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ " "blue"
    Write-Color "  ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗" "blue"
    Write-Color "  ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝" "blue"
    Write-Color "  ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗" "blue"
    Write-Color "  ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║" "blue"
    Write-Color "  ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝" "blue"
    Write-Color "                        for Windows" "white"
    Write-Host ""
}

# ============================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================

$ServiceName = "TorrServer"
$TaskName    = "TorrServer"
$BinName     = "TorrServer-windows-amd64.exe"
$BinPath     = Join-Path $InstallDir $BinName
$VersionFile = Join-Path $InstallDir "version"
$AccsFile    = Join-Path $InstallDir "accs.db"
$LogFile     = Join-Path $InstallDir "torrserver.log"

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestRelease {
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/YouROK/TorrServer/releases/latest" `
            -Headers @{ "User-Agent" = "torrserverwrt-installer" }
        return $release.tag_name
    } catch {
        return $null
    }
}

function Get-InstalledVersion {
    if (Test-Path $VersionFile) { return Get-Content $VersionFile -Raw | ForEach-Object { $_.Trim() } }
    return "unknown"
}

function Test-Installed {
    return (Test-Path $BinPath)
}

function Test-Running {
    # Проверяем сервис, потом задачу, потом просто процесс
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { return $true }
    $proc = Get-Process -Name ($BinName -replace '\.exe$','') -ErrorAction SilentlyContinue
    return ($null -ne $proc)
}

function Get-ServicePort {
    # Ищем порт в аргументах задачи или сервиса
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $args = $task.Actions[0].Arguments
        if ($args -match '--port (\d+)') { return $Matches[1] }
    }
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName -match '--port (\d+)') { return $Matches[1] }
    return "8090"
}

function Get-LocalIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 |
               Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.PrefixOrigin -ne 'WellKnown' } |
               Select-Object -First 1).IPAddress
        if ($ip) { return $ip } else { return "localhost" }
    } catch { return "localhost" }
}

function Get-DiskFreeGB {
    param([string]$Path)
    $drive = Split-Path -Qualifier $Path
    $disk  = Get-PSDrive -Name ($drive -replace ':','') -ErrorAction SilentlyContinue
    if ($disk) { return [math]::Round($disk.Free / 1GB, 1) }
    return 999
}

function Get-AuthCredentials {
    if (-not (Test-Path $AccsFile)) { return $null }
    try {
        $json = Get-Content $AccsFile -Raw | ConvertFrom-Json -ErrorAction Stop
        $user = ($json.PSObject.Properties | Select-Object -First 1)
        if ($user) { return @{ Login = $user.Name; Password = $user.Value } }
    } catch {}
    return $null
}

function Test-AuthEnabled {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $task.Actions[0].Arguments -match '--httpauth') { return $true }
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName -match '--httpauth') { return $true }
    return $false
}

# ============================================================
# УПРАВЛЕНИЕ СЛУЖБОЙ / ЗАДАЧЕЙ
# ============================================================

function Register-TorrServerTask {
    param([string]$Arguments)
    # Предпочитаем Windows Service (NSSM), fallback — Scheduled Task
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    $nssmPath = if ($nssmCmd) { $nssmCmd.Source } else { $null }

    if ($nssmPath) {
        Write-Info "Installing as Windows Service (NSSM)..."
        & nssm install $ServiceName $BinPath | Out-Null
        & nssm set $ServiceName AppParameters $Arguments | Out-Null
        & nssm set $ServiceName AppStdout $LogFile | Out-Null
        & nssm set $ServiceName AppStderr $LogFile | Out-Null
        & nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
        & nssm start $ServiceName | Out-Null
    } else {
        Write-Info "Installing as Scheduled Task (autostart on logon)..."
        $action  = New-ScheduledTaskAction -Execute $BinPath -Argument $Arguments
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
                        -ExecutionTimeLimit ([TimeSpan]::Zero)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName $TaskName
    }
}

function Start-TorrServer {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) { Start-Service $ServiceName -ErrorAction SilentlyContinue; return }
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue; return }
}

function Stop-TorrServer {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) { Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue }
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
    Get-Process -Name ($BinName -replace '\.exe$','') -ErrorAction SilentlyContinue | Stop-Process -Force
}

function Remove-TorrServerService {
    Stop-TorrServer
    $nssmCmd2 = Get-Command nssm -ErrorAction SilentlyContinue
    $nssmPath = if ($nssmCmd2) { $nssmCmd2.Source } else { $null }
    if ($nssmPath) {
        & nssm remove $ServiceName confirm 2>$null | Out-Null
    } else {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    # Правило файрвола
    Remove-NetFirewallRule -DisplayName "TorrServer" -ErrorAction SilentlyContinue
}

function Add-FirewallRule {
    param([int]$RulePort)
    New-NetFirewallRule -DisplayName "TorrServer" `
        -Direction Inbound -Protocol TCP -LocalPort $RulePort `
        -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Info "Firewall rule added for port $RulePort"
}

# ============================================================
# ОСНОВНЫЕ ФУНКЦИИ
# ============================================================

function Download-TorrServer {
    param([string]$Version)

    $url     = "https://github.com/YouROK/TorrServer/releases/download/$Version/$BinName"
    $tmpPath = Join-Path $InstallDir "$BinName.tmp"

    # Проверка места (нужно ~150 МБ при обновлении)
    $freeGB  = Get-DiskFreeGB $InstallDir
    $needGB  = if (Test-Path $BinPath) { 0.15 } else { 0.08 }
    if ($freeGB -lt $needGB) {
        Write-Warn "Low disk space: $freeGB GB free, need $([math]::Round($needGB*1024)) MB"
        if (Test-Path $BinPath) {
            $ans = Read-Host " Remove old binary to free space? (Y/N)"
            if ($ans -match '^[Yy]') {
                Remove-Item $BinPath -Force
                Write-Info "Old binary removed"
            } else {
                Write-Err "Aborted — not enough space"
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
        Write-Err "Downloaded file too small ($size bytes) — wrong version or architecture"
        Remove-Item $tmpPath -Force
        return $false
    }

    Move-Item -Path $tmpPath -Destination $BinPath -Force
    Set-Content -Path $VersionFile -Value $Version -Encoding UTF8
    Write-Ok "Downloaded TorrServer $Version"
    return $true
}

function Install-TorrServer {
    Write-Host ""
    Write-Sep
    Write-Color " TorrServer Installation for Windows" "cyan"
    Write-Sep
    Write-Host ""
    Write-Warn "REQUIREMENTS:"
    Write-Host "  RAM:   256 MB minimum, 512 MB+ recommended"
    Write-Host "  Space: ~80 MB for binary + working directory"
    Write-Host "  OS:    Windows 10/11 or Windows Server 2016+"
    Write-Host ""

    if (Test-Installed) {
        $curVer = Get-InstalledVersion
        Write-Warn "TorrServer already installed (version: $curVer)"
        $ans = Read-Host " Update to latest version? (Y/N)"
        if ($ans -match '^[Yy]') { Update-TorrServer }
        return
    }

    $ans = Read-Host " Proceed with installation? (Y/N)"
    if ($ans -notmatch '^[Yy]') { Write-Host " Cancelled"; return }

    # Создаём папку
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Версия
    Write-Info "Fetching latest version..."
    $latest = Get-LatestRelease
    if (-not $latest) { Write-Err "Could not fetch version from GitHub"; return }
    Write-Info "Latest version: $latest"

    # Скачиваем
    if (-not (Download-TorrServer $latest)) { return }

    # Порт
    $servicePort = $Port
    $ans = Read-Host " Change port? Default is $Port (Y/N)"
    if ($ans -match '^[Yy]') {
        $p = Read-Host " Enter port (1024-65535)"
        if ($p -match '^\d+$' -and [int]$p -ge 1024 -and [int]$p -le 65535) {
            $servicePort = [int]$p
        } else {
            Write-Warn "Invalid port, using $Port"
        }
    }

    # Авторизация
    $authArgs = "--port $servicePort --path `"$InstallDir`""
    $authUser = ""; $authPass = ""
    $ans = Read-Host " Enable HTTP authorization? (Y/N)"
    if ($ans -match '^[Yy]') {
        $authUser = Read-Host " Username"
        $secPass  = Read-Host " Password" -AsSecureString
        $authPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass))
        $json = "{\n  `"$authUser`": `"$authPass`"\n}"
        Set-Content -Path $AccsFile -Value $json -Encoding UTF8
        $authArgs += " --httpauth"
        Write-Ok "Credentials saved"
    }

    # Регистрируем службу / задачу
    Register-TorrServerTask -Arguments $authArgs

    # Правило файрвола
    $ans = Read-Host " Add Windows Firewall rule for port $servicePort? (Y/N)"
    if ($ans -match '^[Yy]') { Add-FirewallRule -RulePort $servicePort }

    Start-Sleep -Seconds 2

    $ip = Get-LocalIP
    Write-Host ""
    Write-Sep
    if (Test-Running) {
        Write-Ok "TorrServer $latest installed and RUNNING"
    } else {
        Write-Warn "TorrServer $latest installed but did not start"
        Write-Host "  Check log: $LogFile"
    }
    Write-Sep
    Write-Color " Web UI:  http://${ip}:${servicePort}" "cyan"
    if ($authUser) { Write-Host " Login:   $authUser   Password: $authPass" }
    Write-Host " Log:     $LogFile"
    Write-Host ""
}

function Update-TorrServer {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }

    Write-Info "Fetching latest version..."
    $latest  = Get-LatestRelease
    if (-not $latest) { Write-Err "Could not fetch version from GitHub"; return }
    $current = Get-InstalledVersion
    Write-Host " Installed: $current  |  Latest: $latest"

    if ($current -eq $latest) { Write-Ok "Already up to date"; return }

    Write-Info "Stopping service..."
    Stop-TorrServer
    Start-Sleep -Seconds 2

    if (-not (Download-TorrServer $latest)) {
        Write-Warn "Download failed, restarting old version..."
        Start-TorrServer
        return
    }

    Start-TorrServer
    Start-Sleep -Seconds 2

    if (Test-Running) { Write-Ok "TorrServer updated to $latest and RUNNING" }
    else { Write-Warn "Updated to $latest but did not start — check: $LogFile" }
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

    $version = Get-InstalledVersion
    $port    = Get-ServicePort
    $ip      = Get-LocalIP

    Write-Host " Version:  $version"
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
        } else {
            Write-Color " Auth:     ON (accs.db missing!)" "red"
        }
    } else {
        Write-Color " Auth:     OFF" "cyan"
    }

    # Автообновление через Task Scheduler
    $updTask = Get-ScheduledTask -TaskName "TorrServerUpdate" -ErrorAction SilentlyContinue
    if ($updTask) { Write-Color " Auto-upd: ON" "green" }
    else          { Write-Color " Auto-upd: OFF" "cyan" }

    # Проверка обновления
    Write-Host " Update:   " -NoNewline
    $latest = Get-LatestRelease
    if ($latest -and $latest -ne $version) {
        Write-Color "available $latest" "yellow"
    } elseif ($latest) {
        Write-Color "not required" "green"
    } else {
        Write-Host "could not check"
    }

    Write-Sep; Write-Host ""
}

function Remove-TorrServer {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }

    Write-Host ""
    Write-Host " Directory: $InstallDir"
    Write-Host " Version:   $(Get-InstalledVersion)"
    Write-Host ""
    Write-Color " WARNING: All data including torrent database will be deleted!" "red"
    Write-Host ""
    $ans = Read-Host " Are you sure? (Y/N)"
    if ($ans -notmatch '^[Yy]') { Write-Host " Cancelled"; return }

    Remove-TorrServerService

    # Удаляем задачу автообновления если есть
    Unregister-ScheduledTask -TaskName "TorrServerUpdate" -Confirm:$false -ErrorAction SilentlyContinue

    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "TorrServer removed"
    Write-Host ""
}

function Set-AutoUpdate {
    # Еженедельная проверка через Task Scheduler — воскресенье 04:00
    $updTask = Get-ScheduledTask -TaskName "TorrServerUpdate" -ErrorAction SilentlyContinue
    if ($updTask) {
        Write-Host " Auto-update already configured (weekly, Sunday 04:00)"
        $ans = Read-Host " Disable? (Y/N)"
        if ($ans -match '^[Yy]') {
            Unregister-ScheduledTask -TaskName "TorrServerUpdate" -Confirm:$false
            Write-Ok "Auto-update disabled"
        }
        return
    }

    Write-Host ""
    Write-Host " Auto-update: checks weekly (Sunday, 04:00), downloads ~70 MB only if new version available"
    Write-Host " Log: $InstallDir\update.log"
    Write-Host ""
    $ans = Read-Host " Enable auto-update? (Y/N)"
    if ($ans -notmatch '^[Yy]') { Write-Host " Cancelled"; return }

    $scriptPath = $MyInvocation.ScriptName
    $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`" -Action update -NoColor >> `"$InstallDir\update.log`" 2>&1"
    $trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "04:00"
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    $principal= New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
    Register-ScheduledTask -TaskName "TorrServerUpdate" -Action $action `
        -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Ok "Auto-update enabled (Sunday 04:00)"
}

function Show-Help {
    Write-Host @"

Usage: .\install.ps1 [options]

Parameters:
  -Action     install | update | status | remove   Action to perform
  -Port       <number>                             Port (default: 8090)
  -InstallDir <path>                               Install directory (default: C:\TorrServer)
  -NoColor                                         Disable colored output

Examples:
  .\install.ps1
  .\install.ps1 -Action install -Port 9090
  .\install.ps1 -Action update
  .\install.ps1 -Action status
  .\install.ps1 -Action remove

"@
}

# ============================================================
# ТОЧКА ВХОДА
# ============================================================

# Проверка прав администратора
if (-not (Test-Admin)) {
    Write-Color " [ERR] Run as Administrator!" "red"
    Write-Host " Right-click PowerShell → Run as Administrator"
    Write-Host " Or use install.bat (it handles this automatically)"
    exit 1
}

switch ($Action.ToLower()) {
    "install" { Install-TorrServer }
    "update"  { Update-TorrServer  }
    "status"  { Show-Status        }
    "remove"  { Remove-TorrServer  }
    "help"    { Show-Help          }
    default   {
        # Интерактивное меню
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

        while ($true) {
            $choice = Read-Host " Choice"
            switch ($choice.ToLower()) {
                "i" { Install-TorrServer; break }
                "s" { Show-Status }
                "c" { Set-AutoUpdate }
                "d" { Remove-TorrServer; break }
                "q" { break }
                default { Write-Host " Enter i, s, c, d or q" }
            }
            if ($choice -match '^[iqd]$') { break }
        }
    }
}
