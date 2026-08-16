@echo off
chcp 65001 >nul 2>&1
title TorrServer Installer

:: Проверяем наличие PowerShell
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERR] PowerShell not found. Please install PowerShell.
    pause
    exit /b 1
)

:: Запускаем установщик напрямую из интернета
:: -ExecutionPolicy Bypass обходит любые политики без изменения системных настроек
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { irm https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.ps1 | iex }"

if %errorlevel% neq 0 (
    echo.
    echo [!!] Something went wrong. Trying alternative method...
    echo.
    :: Альтернативный способ — скачиваем файл и запускаем
    set "tmpfile=%TEMP%\torrserver_install.ps1"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.ps1' -OutFile '%tmpfile%'"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%tmpfile%"
    del "%tmpfile%" >nul 2>&1
)

pause
