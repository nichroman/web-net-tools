@echo off
cd /d "%~dp0"
start cmd /k npm start
timeout /t 3 /nobreak >nul
start "" http://localhost:3000