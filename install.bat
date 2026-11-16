@echo off
chcp 65001 >nul 2>&1
title TorrServer Installer

:: --- Self-elevate to Administrator (install.ps1 requires it) ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  Requesting Administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  TorrServer Installer for Windows
echo  ================================
echo.
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERR] PowerShell not found
    pause
    exit /b 1
)

set "tmpfile=%TEMP%\torrserver_install.ps1"
echo  Downloading installer...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.ps1' -OutFile '%tmpfile%'; exit 0 } catch { Write-Host $_; exit 1 }"
if %errorlevel% neq 0 (
    echo [ERR] Download failed. Check internet connection.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%tmpfile%" %*
del "%tmpfile%" >nul 2>&1
echo.
pause
