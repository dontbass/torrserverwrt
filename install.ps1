# TorrServer Installer for Windows
# Compatible with PowerShell 5.1+ (built-in on Windows 10/11)
# Usage: run install.bat OR powershell -ExecutionPolicy Bypass -File install.ps1

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

$InstallDir  = "C:\TorrServer"
$DefaultPort = 8090
$ServiceName = "TorrServer"
$TaskName    = "TorrServer"
$BinName     = "TorrServer-windows-amd64.exe"
$BinPath     = Join-Path $InstallDir $BinName
$VersionFile = Join-Path $InstallDir "version"
$BranchFile  = Join-Path $InstallDir "branch"
$ConfigYaml  = Join-Path $InstallDir "config.yaml"
$AccsFile    = Join-Path $InstallDir "accs.db"
$LogFile     = Join-Path $InstallDir "torrserver.log"
$ScriptUrl   = "https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.ps1"

# "matrix" (Lampa compatible) or "silo" (new rewrite) — set by Initialize-Branch
$script:Branch = "matrix"

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

# PS5.1 Set-Content -Encoding UTF8 adds BOM — Go parsers fail on it. Always write without BOM.
function Write-NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

# Fix accs.db BOM if present (older versions of this script wrote it with BOM)
function Repair-AccsDb {
    if (-not (Test-Path $AccsFile)) { return }
    $bytes = [System.IO.File]::ReadAllBytes($AccsFile)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Warn "accs.db has UTF-8 BOM — fixing (this caused auth failure)"
        $noBom = $bytes[3..($bytes.Length - 1)]
        [System.IO.File]::WriteAllBytes($AccsFile, $noBom)
        Write-Ok "accs.db fixed — restart TorrServer to apply"
    }
}

# ============================================================
# BRANCH (MatriX / Silo)
# ============================================================

function Save-Branch {
    param([string]$Name)
    $script:Branch = $Name
    if (Test-Path $InstallDir) { Write-NoBom $BranchFile $Name }
}

function Initialize-Branch {
    if (Test-Path $BranchFile) {
        $b = (Get-Content $BranchFile -Raw).Trim().ToLower()
        if ($b -eq "silo" -or $b -eq "matrix") { $script:Branch = $b; return }
    }
    # No branch file (installed by an older script) — detect from installed version tag
    $ver = Get-InstalledVersion
    if ($ver -match "silo") { Save-Branch "silo" }
    elseif (Test-Path $InstallDir) { Save-Branch "matrix" }
    else { $script:Branch = "matrix" }
}

function Test-Silo { return ($script:Branch -eq "silo") }

function Get-BranchLabel {
    if (Test-Silo) { return "Silo (experimental, Lampa NOT supported)" }
    return "MatriX (Lampa compatible)"
}

function Select-Branch {
    Write-Host ""
    Write-Host " Select TorrServer branch:"
    Write-Color "  1 - MatriX (recommended, Lampa compatible)" "green"
    Write-Color "  2 - Silo   (new rewrite, Lampa NOT supported yet)" "yellow"
    $c = Read-Host " Choice (Enter = 1)"
    if ($c -eq "2") { Save-Branch "silo";   Write-Ok "Branch: Silo" }
    else            { Save-Branch "matrix"; Write-Ok "Branch: MatriX" }
}

# ============================================================
# VERSIONS
# ============================================================

function Get-LatestRelease {
    $hdr = @{ "User-Agent" = "torrserverwrt" }
    try {
        if (Test-Silo) {
            $r = Invoke-RestMethod "https://api.github.com/repos/YouROK/TorrServer/releases/latest" -Headers $hdr
            return $r.tag_name
        }
        # MatriX — newest non-prerelease release whose tag starts with "MatriX"
        $list = Invoke-RestMethod "https://api.github.com/repos/YouROK/TorrServer/releases?per_page=50" -Headers $hdr
        $m = $list | Where-Object { $_.tag_name -match "^MatriX" -and -not $_.prerelease } | Select-Object -First 1
        if ($m) { return $m.tag_name }
    } catch {}
    return $null
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

# ============================================================
# CONFIG (port / auth) — Silo: config.yaml, MatriX: task args + accs.db
# ============================================================

function Get-TaskArguments {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { return [string]$task.Actions[0].Arguments }
    $svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($svc) { return [string]$svc.PathName }
    return ""
}

function Get-YamlPort {
    if (-not (Test-Path $ConfigYaml)) { return $null }
    $m = Select-String -Path $ConfigYaml -Pattern "^\s*port:\s*(\d+)" | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return $null
}

function Get-YamlPassword {
    if (-not (Test-Path $ConfigYaml)) { return "" }
    $m = Select-String -Path $ConfigYaml -Pattern "^\s*owner_password:\s*`"?([^`"]*)`"?" | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    return ""
}

function Get-ArgsPort {
    $a = Get-TaskArguments
    if ($a -match "--port (\d+)") { return $Matches[1] }
    return $null
}

function Get-ServicePort {
    $p = $null
    if (Test-Silo) { $p = Get-YamlPort }
    if (-not $p)   { $p = Get-ArgsPort }
    if (-not $p)   { $p = Get-YamlPort }
    if (-not $p)   { $p = "$DefaultPort" }
    return $p
}

function Get-AccsCredentials {
    if (-not (Test-Path $AccsFile)) { return $null }
    try {
        $json = Get-Content $AccsFile -Raw | ConvertFrom-Json
        $prop = $json.PSObject.Properties | Select-Object -First 1
        if ($prop) { return @{ Login = $prop.Name; Password = [string]$prop.Value } }
    } catch {}
    return $null
}

function Get-AuthCredentials {
    if (Test-Silo) {
        $p = Get-YamlPassword
        if ($p) { return @{ Login = "owner"; Password = $p } }
        return $null
    }
    return Get-AccsCredentials
}

function Test-AuthEnabled {
    if (Test-Silo) { return [bool](Get-YamlPassword) }
    return ((Test-Path $AccsFile) -and ($null -ne (Get-AccsCredentials)))
}

function Write-ConfigYaml {
    param([string]$Port, [string]$OwnerPass = "")
    $dataDir   = (Join-Path $InstallDir "data")    -replace "\\","/"
    $pluginDir = (Join-Path $InstallDir "plugins") -replace "\\","/"
    New-Item -ItemType Directory -Path (Join-Path $InstallDir "data")    -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $InstallDir "plugins") -Force | Out-Null
    $yaml = @"
server:
    host: 0.0.0.0
    port: $Port
storage:
    data_dir: "$dataDir"
    db_name: torrserver.db
plugins:
    dir: "$pluginDir"
torrent:
    cache_size_mb: 200
    peers_limit: 200
    download_rate_kb: 0
    upload_rate_kb: 0
logging:
    level: info
    file: ""
auth:
    owner_password: "$OwnerPass"
ffmpeg:
    enabled: false
    path: ""
    probe_path: ""
"@
    Write-NoBom $ConfigYaml ($yaml -replace "`r`n","`n")
}

function Write-AccsDb {
    param([string]$Login, [string]$Password)
    if (-not $Login) { $Login = "owner" }
    Write-NoBom $AccsFile "{`n  `"$Login`": `"$Password`"`n}`n"
}

# Start arguments for the current branch
function Get-StartArgs {
    param([string]$Port)
    if (Test-Silo) { return "-c `"$ConfigYaml`"" }
    $a = "--port $Port --path `"$InstallDir`""
    if (Test-AuthEnabled) { $a += " --httpauth" }
    return $a
}

# ============================================================
# SERVICE MANAGEMENT
# ============================================================

function Register-AsTask {
    param([string]$Arguments)
    Write-Info "Registering Scheduled Task (SYSTEM, starts with Windows)..."
    $action    = New-ScheduledTaskAction -Execute $BinPath -Argument $Arguments -WorkingDirectory $InstallDir
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

# Re-create task with arguments matching current branch/config, then start
function Update-TaskConfig {
    param([string]$Port)
    if (-not $Port) { $Port = Get-ServicePort }
    # Old NSSM service would hold the old args — remove it, Task Scheduler is used now
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd -and (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        & nssm.exe remove $ServiceName confirm 2>$null | Out-Null
    }
    Register-AsTask -Arguments (Get-StartArgs -Port $Port)
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
    $procName = $BinName -replace "\.exe$",""
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force
    # Wait for the process to fully exit so the .exe and DB files are unlocked
    $waited = 0
    while ((Get-Process -Name $procName -ErrorAction SilentlyContinue) -and $waited -lt 10) {
        Start-Sleep -Seconds 1; $waited++
    }
    Start-Sleep -Milliseconds 500
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
    Remove-NetFirewallRule -DisplayName "TorrServer" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "TorrServer" `
        -Direction Inbound -Protocol TCP -LocalPort $RulePort `
        -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Info "Firewall rule set for port $RulePort"
}

function Wait-Running {
    for ($i = 0; $i -lt 6; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Running) { return $true }
    }
    return (Test-Running)
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
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
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
    Write-NoBom $VersionFile $Version
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
        Write-Warn "Already installed (version: $(Get-InstalledVersion), branch: $(Get-BranchLabel))"
        $ans = Read-Host " Update to latest $(if (Test-Silo) {'Silo'} else {'MatriX'})? (Y/N)"
        if ($ans -match "^[Yy]") { Update-TorrServer }
        return
    }

    $ans = Read-Host " Proceed with installation? (Y/N)"
    if ($ans -notmatch "^[Yy]") { Write-Host " Cancelled"; return }

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    Select-Branch

    Write-Info "Fetching latest version..."
    $latest = Get-LatestRelease
    if (-not $latest) { Write-Err "Could not get version from GitHub"; return }
    Write-Info "Latest version: $latest"

    if (-not (Download-TorrServer $latest)) { return }

    # Port
    $port = "$DefaultPort"
    $p = Read-Host " Port (press Enter for default $DefaultPort)"
    if ($p -match "^\d+$" -and [int]$p -ge 1024 -and [int]$p -le 65535) { $port = $p }

    # Auth
    $authUser = ""; $authPass = ""
    $ans = Read-Host " Enable HTTP authorization? (Y/N)"
    if ($ans -match "^[Yy]") {
        if (Test-Silo) {
            $authUser = "owner"   # Silo has a single owner account
        } else {
            $authUser = Read-Host " Username (Enter = owner)"
            if (-not $authUser) { $authUser = "owner" }
        }
        $authPass = Read-Host " Password"
        Write-Ok "Credentials saved"
    }

    if (Test-Silo) {
        Write-ConfigYaml -Port $port -OwnerPass $authPass
    } elseif ($authPass) {
        Write-AccsDb -Login $authUser -Password $authPass
    }

    Update-TaskConfig -Port $port

    # Firewall
    $ans = Read-Host " Add firewall rule for port ${port}? (Y/N)"
    if ($ans -match "^[Yy]") { Add-FWRule -RulePort ([int]$port) }

    $ok = Wait-Running
    $ip = Get-LocalIP

    Write-Host ""
    Write-Sep
    if ($ok) { Write-Ok "TorrServer $latest installed and RUNNING" }
    else     { Write-Warn "Installed but did not start. Check log: $LogFile" }
    Write-Sep
    Write-Host " Branch:  $(Get-BranchLabel)"
    Write-Color " Web UI:  http://${ip}:${port}" "cyan"
    if ($authPass) { Write-Host " Login:   $authUser   Password: $authPass" }
    Write-Host " Log:     $LogFile"
    Write-Host ""
}

function Update-TorrServer {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }
    Write-Info "Branch: $(Get-BranchLabel)"
    Write-Info "Fetching latest version..."
    $latest = Get-LatestRelease
    if (-not $latest) { Write-Err "Could not get version"; return }
    $cur = Get-InstalledVersion
    Write-Host " Installed: $cur  |  Latest: $latest"

    $port = Get-ServicePort
    # Silo needs config.yaml — migrate from old --port/accs.db setup if missing
    if ((Test-Silo) -and -not (Test-Path $ConfigYaml)) {
        $c = Get-AccsCredentials
        $pass = if ($c) { $c.Password } else { "" }
        Write-ConfigYaml -Port $port -OwnerPass $pass
        Write-Ok "Created config.yaml (port $port)"
    }

    if ($cur -eq $latest) {
        # Same version, but task args may be from an old script (e.g. Silo started with --port) — repair
        $want = Get-StartArgs -Port $port
        if ((Get-TaskArguments) -ne $want) {
            Write-Warn "Service start arguments are outdated — fixing"
            Stop-Torr
            Update-TaskConfig -Port $port
            if (Wait-Running) { Write-Ok "Service restarted with correct arguments" }
            else { Write-Warn "Service did not start. Check: $LogFile" }
        } else {
            Write-Ok "Already up to date"
        }
        return
    }

    Write-Info "Stopping service..."
    Stop-Torr
    if (-not (Download-TorrServer $latest)) {
        Write-Warn "Download failed, restarting old version..."
        Start-Torr; return
    }
    Update-TaskConfig -Port $port
    if (Wait-Running) { Write-Ok "Updated to $latest" }
    else { Write-Warn "Updated but did not start. Check: $LogFile" }
}

function Switch-Branch {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }
    $old = $script:Branch
    $new = if ($old -eq "silo") { "matrix" } else { "silo" }
    Write-Host ""
    Write-Host " Current branch: $(Get-BranchLabel)"
    if ($new -eq "silo") {
        Write-Color " WARNING: switching to Silo. Lampa will NOT work." "yellow"
    } else {
        Write-Color " Switching to MatriX. Lampa will work again. config.yaml will be backed up." "yellow"
    }
    $ans = Read-Host " Continue? (Y/N)"
    if ($ans -notmatch "^[Yy]") { Write-Host " Cancelled"; return }

    # Collect current settings before switching
    $port  = Get-ServicePort
    $creds = Get-AuthCredentials

    $script:Branch = $new
    Write-Info "Fetching latest $(if ($new -eq 'silo') {'Silo'} else {'MatriX'}) version..."
    $latest = Get-LatestRelease
    if (-not $latest) { Write-Err "Could not get version"; $script:Branch = $old; return }
    Write-Info "Target version: $latest"

    Write-Info "Stopping service..."
    Stop-Torr
    if (-not (Download-TorrServer $latest)) {
        Write-Warn "Download failed — staying on previous branch"
        $script:Branch = $old
        Start-Torr; return
    }
    Save-Branch $new

    # Migrate config
    if ($new -eq "silo") {
        $pass = if ($creds) { $creds.Password } else { "" }
        Write-ConfigYaml -Port $port -OwnerPass $pass
        Write-Ok "config.yaml created (port $port)"
    } else {
        if (Test-Path $ConfigYaml) {
            Move-Item $ConfigYaml "$ConfigYaml.bak" -Force
            Write-Info "config.yaml backed up to config.yaml.bak"
        }
        if ($creds -and $creds.Password) { Write-AccsDb -Login $creds.Login -Password $creds.Password }
        else { Remove-Item $AccsFile -Force -ErrorAction SilentlyContinue }
    }

    Update-TaskConfig -Port $port
    if (Wait-Running) {
        Write-Ok "Switched to $(Get-BranchLabel) — $latest RUNNING"
        Write-Color " Web UI: http://$(Get-LocalIP):$port" "cyan"
    } else {
        Write-Warn "Switched to $latest but service did not start. Check: $LogFile"
    }
}

function Set-Port {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }
    $cur = Get-ServicePort
    Write-Host " Current port: $cur"
    $p = Read-Host " New port (1024-65535)"
    if (-not ($p -match "^\d+$" -and [int]$p -ge 1024 -and [int]$p -le 65535)) {
        Write-Err "Invalid port"; return
    }
    if (Test-Silo) {
        Write-ConfigYaml -Port $p -OwnerPass (Get-YamlPassword)
    }
    Stop-Torr
    Update-TaskConfig -Port $p
    if (Get-NetFirewallRule -DisplayName "TorrServer" -ErrorAction SilentlyContinue) {
        Add-FWRule -RulePort ([int]$p)
    }
    if (Wait-Running) { Write-Ok "Port changed: http://$(Get-LocalIP):$p" }
    else { Write-Warn "Service did not start. Check: $LogFile" }
}

function Set-Auth {
    if (-not (Test-Installed)) { Write-Err "TorrServer is not installed"; return }
    $port = Get-ServicePort
    $c = Get-AuthCredentials
    if ($c) { Write-Host " Auth: ON (login: $($c.Login))" } else { Write-Host " Auth: OFF" }
    Write-Host "  1 - set / change password"
    Write-Host "  2 - disable authorization"
    $ch = Read-Host " Choice"
    switch ($ch) {
        "1" {
            $login = "owner"
            if (-not (Test-Silo)) {
                $login = Read-Host " Username (Enter = owner)"
                if (-not $login) { $login = "owner" }
            }
            $pass = Read-Host " Password"
            if (-not $pass) { Write-Err "Empty password"; return }
            if (Test-Silo) { Write-ConfigYaml -Port $port -OwnerPass $pass }
            else           { Write-AccsDb -Login $login -Password $pass }
            Write-Ok "Authorization enabled"
        }
        "2" {
            if (Test-Silo) { Write-ConfigYaml -Port $port -OwnerPass "" }
            else           { Remove-Item $AccsFile -Force -ErrorAction SilentlyContinue }
            Write-Ok "Authorization disabled"
        }
        default { Write-Host " Cancelled"; return }
    }
    Stop-Torr
    Update-TaskConfig -Port $port
    if (Wait-Running) { Write-Ok "Settings applied" }
    else { Write-Warn "Service did not start. Check: $LogFile" }
}

function Show-Status {
    Write-Host ""
    Write-Sep
    Write-Color " TorrServer Status" "cyan"
    Write-Sep
    Repair-AccsDb
    if (-not (Test-Installed)) {
        Write-Color " State:    NOT INSTALLED" "red"
        Write-Sep; Write-Host ""; return
    }
    $ver  = Get-InstalledVersion
    $port = Get-ServicePort
    $ip   = Get-LocalIP
    Write-Host " Version:  $ver"
    Write-Host " Binary:   $BinName"
    if (Test-Silo) { Write-Color " Branch:   $(Get-BranchLabel)" "yellow" }
    else           { Write-Color " Branch:   $(Get-BranchLabel)" "green"  }
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
    Write-Host " Branch is kept: $(Get-BranchLabel)"
    $ans = Read-Host " Enable? (Y/N)"
    if ($ans -notmatch "^[Yy]") { Write-Host " Cancelled"; return }
    # When launched via "irm | iex" there is no script file — save a local copy for the task
    $scriptPath = Join-Path $InstallDir "install.ps1"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        (New-Object System.Net.WebClient).DownloadFile($ScriptUrl, $scriptPath)
    } catch {
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) { Copy-Item $PSCommandPath $scriptPath -Force }
    }
    if (-not (Test-Path $scriptPath)) { Write-Err "Could not save install.ps1 to $InstallDir"; return }
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

Initialize-Branch

switch ($Action) {
    "install" { Install-TorrServer }
    "update"  { Update-TorrServer  }
    "status"  { Show-Status        }
    "branch"  { Switch-Branch      }
    "remove"  { Remove-TorrServer  }
    default   {
        Show-Logo
        if (Test-Installed) {
            Write-Host " Version: $(Get-InstalledVersion)"
            if (Test-Silo) { Write-Color " Branch:  $(Get-BranchLabel)" "yellow" }
            else           { Write-Color " Branch:  $(Get-BranchLabel)" "green"  }
            if (Test-Running) { Write-Color " Service: RUNNING" "green" }
            else              { Write-Color " Service: STOPPED" "red"   }
        }
        Write-Host ""
        Write-Color "  [i] install / update"              "green"
        Write-Color "  [s] status"                        "cyan"
        Write-Color "  [b] switch branch (MatriX <-> Silo)" "blue"
        Write-Color "  [p] change port"                   "cyan"
        Write-Color "  [a] authorization"                 "cyan"
        Write-Color "  [c] auto-update"                   "cyan"
        Write-Color "  [d] remove"                        "red"
        Write-Color "  [q] quit"                          "yellow"
        Write-Host ""
        $running = $true
        while ($running) {
            $choice = Read-Host " Choice"
            switch ($choice.ToLower()) {
                "i" { Install-TorrServer; $running = $false }
                "s" { Show-Status }
                "b" { Switch-Branch; $running = $false }
                "p" { Set-Port; $running = $false }
                "a" { Set-Auth; $running = $false }
                "c" { Set-AutoUpdate }
                "d" { Remove-TorrServer; $running = $false }
                "q" { $running = $false }
                default { Write-Host " Enter i, s, b, p, a, c, d or q" }
            }
        }
    }
}
