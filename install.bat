@echo off
rem =====================================================================
rem  Web_NetTools v0.0.3 - установка программ для всех пользователей.
rem  Запускайте этот файл двойным щелчком: права администратора
rem  запрашиваются автоматически (UAC).
rem
rem  Дополнительные параметры install.ps1 можно передать так:
rem     install.bat -InstallDir "D:\Tools\WebNetTools"
rem =====================================================================
setlocal

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    if "%~1"=="" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

echo Installing Web_NetTools (WEB_check_nodes + WEB_check_ports)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
echo Exit code: %ERRORLEVEL%
echo.
pause
endlocal
