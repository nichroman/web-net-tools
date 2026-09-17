# ==========================================================================
#  Web_NetTools v0.0.1 - start-check-nodes.ps1
#  Ярлык "Проверка узлов (Web_NetTools)" на общем рабочем столе:
#  запускает WEB_check_nodes (порт 3000) скрыто и открывает браузер.
#
#  Параметры (нужны только для диагностики и автотестов):
#     -AppDir    каталог приложения (по умолчанию <установка>\check-nodes)
#     -Port      порт сервера (по умолчанию 3000)
#     -NoBrowser не открывать браузер
#     -NoDialogs не показывать диалоговые окна (сообщения только в журнал)
# ==========================================================================

param(
    [string]$AppDir = '',
    [int]$Port = 3000,
    [switch]$NoBrowser,
    [switch]$NoDialogs
)

$launcherDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $launcherDir 'webnettools-common.ps1')

$root = Split-Path -Parent $launcherDir
if ($AppDir -eq '') {
    $AppDir = Join-Path $root 'check-nodes'
}
$logFile = Join-Path $root 'logs\check-nodes.log'

exit (Start-WebNetTool -Name 'WEB_check_nodes (проверка узлов)' `
    -AppDir $AppDir `
    -Port $Port `
    -HealthMarker 'WEB_check_nodes' `
    -LogFile $logFile `
    -NoBrowser:$NoBrowser `
    -NoDialogs:$NoDialogs)
