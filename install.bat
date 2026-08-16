@echo off
chcp 65001 >nul 2>&1
title TorrServer Installer
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
echo  Downloading installer...
set "tmpfile=%TEMP%\torrserver_install.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.ps1' -OutFile $env:TEMP\torrserver_install.ps1"
if %errorlevel% neq 0 (
    echo [ERR] Download failed. Check internet connection.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\torrserver_install.ps1"
del "%TEMP%\torrserver_install.ps1" >nul 2>&1
pause
