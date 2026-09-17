# ==========================================================================
#  Web_NetTools v0.0.1 - start-check-ports.ps1
#  Ярлык "Проверка портов (Web_NetTools)" на общем рабочем столе:
#  запускает WEB_check_ports (порт 3001) скрыто и открывает браузер.
#
#  Параметры (нужны только для диагностики и автотестов):
#     -AppDir      каталог приложения (по умолчанию <установка>\check-ports)
#     -Port        порт сервера (по умолчанию 3001)
#     -BindAddress адрес прослушивания (по умолчанию 127.0.0.1)
#     -NoBrowser   не открывать браузер
#     -NoDialogs   не показывать диалоговые окна (сообщения только в журнал)
# ==========================================================================

param(
    [string]$AppDir = '',
    [int]$Port = 3001,
    [string]$BindAddress = '127.0.0.1',
    [switch]$NoBrowser,
    [switch]$NoDialogs
)

$launcherDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $launcherDir 'webnettools-common.ps1')

$root = Split-Path -Parent $launcherDir
if ($AppDir -eq '') {
    $AppDir = Join-Path $root 'check-ports'
}
$logFile = Join-Path $root 'logs\check-ports.log'

exit (Start-WebNetTool -Name 'WEB_check_ports (проверка портов)' `
    -AppDir $AppDir `
    -Port $Port `
    -BindAddress $BindAddress `
    -HealthMarker 'WEB_check_ports' `
    -LogFile $logFile `
    -NoBrowser:$NoBrowser `
    -NoDialogs:$NoDialogs)
