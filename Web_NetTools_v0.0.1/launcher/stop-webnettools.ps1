# ==========================================================================
#  Web_NetTools v0.0.1 - stop-webnettools.ps1
#  Остановка серверов WEB_check_nodes (3000) и WEB_check_ports (3001).
#  Ярлык "Остановить серверы Web_NetTools" запускает скрипт с ключом -NoExit,
#  поэтому окно с результатом остаётся открытым.
#
#  Примечание: процесс другого пользователя можно остановить только из-под
#  администратора (ограничение Windows).
# ==========================================================================

param(
    [int[]]$Ports = @(3000, 3001),
    [string]$AppRoot = ''
)

$launcherDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $launcherDir 'webnettools-common.ps1')

if ($AppRoot -eq '') { $AppRoot = Split-Path -Parent $launcherDir }

Write-Host ''
Write-Host 'Остановка серверов Web_NetTools...' -ForegroundColor Cyan
Write-Host ('Каталог установки: ' + $AppRoot)
Write-Host ''

$report = Stop-WebNetToolProcess -Ports $Ports -AppRoot $AppRoot

if ($report.Count -eq 0) {
    Write-Host 'Запущенные серверы Web_NetTools не найдены.' -ForegroundColor Green
} else {
    foreach ($item in $report) {
        Write-Host (' - ' + $item)
    }
}

Write-WebNetToolsLog -LogFile (Join-Path $AppRoot 'logs\stop.log') -Message ('остановка: ' + ($report -join '; '))

Write-Host ''
Write-Host 'Готово.'
