@echo off
rem =====================================================================
rem  Web_NetTools v0.0.1 - удаление установки (ярлыки + каталог программ).
rem  Запускайте этот файл двойным щелчком: права администратора
rem  запрашиваются автоматически (UAC).
rem
rem  Без запроса подтверждения: uninstall.bat -Force
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

echo Removing Web_NetTools...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
echo.
echo Exit code: %ERRORLEVEL%
echo.
pause
endlocal
