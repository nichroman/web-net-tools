<#
    Web_NetTools v0.0.2 - uninstall.ps1
    Удаление установки: остановка серверов, удаление ярлыков и каталога установки.

    Запуск (нужны права администратора):
        uninstall.bat                              - двойной клик, UAC запрашивается сам
        powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1 -Force

    Параметры:
        -InstallDir    каталог установки (по умолчанию C:\Tools\WebNetTools)
        -DesktopDir    каталог ярлыков всех пользователей
        -StartMenuDir  каталог общего меню "Пуск"
        -SkipShortcuts не удалять ярлыки
        -Force         удалять без запроса подтверждения
#>

param(
    [string]$InstallDir = 'C:\Tools\WebNetTools',
    [string]$DesktopDir = '',
    [string]$StartMenuDir = '',
    [switch]$SkipShortcuts,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptPath = $MyInvocation.MyCommand.Definition
$projectDir = Split-Path -Parent $scriptPath
$launcherSource = Join-Path $projectDir 'launcher'

$menuFolderName    = 'Web_NetTools'
$shortcutNodesName = 'Проверка узлов (Web_NetTools)'
$shortcutPortsName = 'Проверка портов (Web_NetTools)'

if ($DesktopDir -eq '') { $DesktopDir = [Environment]::GetFolderPath('CommonDesktopDirectory') }
if ($StartMenuDir -eq '') {
    $StartMenuDir = Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) 'Programs'
}

function Show-Head([string]$Text) { Write-Host ''; Write-Host ('=== ' + $Text) -ForegroundColor Cyan }
function Show-Ok([string]$Text) { Write-Host ('  [ok] ' + $Text) -ForegroundColor Green }
function Show-Info([string]$Text) { Write-Host ('       ' + $Text) }
function Show-Err([string]$Text) { Write-Host ('  [x] ' + $Text) -ForegroundColor Red }

Show-Head 'Web_NetTools v0.0.2 - удаление'
Show-Info ('Каталог установки : ' + $InstallDir)
Show-Info ('Рабочий стол      : ' + $DesktopDir)
Show-Info ('Меню "Пуск"       : ' + $StartMenuDir)

try {
    if (-not $Force) {
        $answer = Read-Host 'Удалить ярлыки и каталог установки? Введите yes для продолжения'
        if ($answer -ne 'yes') {
            Show-Info 'Отменено пользователем'
            exit 1
        }
    }

    . (Join-Path $launcherSource 'webnettools-common.ps1')

    Show-Head '1. Остановка серверов'
    $report = Stop-WebNetToolProcess -Ports @(3000, 3001) -AppRoot $InstallDir
    if ($report.Count -eq 0) {
        Show-Info 'Запущенные серверы не найдены'
    } else {
        foreach ($item in $report) { Show-Info $item }
    }

    if (-not $SkipShortcuts) {
        Show-Head '2. Удаление ярлыков'
        foreach ($name in @($shortcutNodesName, $shortcutPortsName)) {
            $path = Join-Path $DesktopDir ($name + '.lnk')
            if (Test-Path $path) {
                Remove-Item -Path $path -Force
                Show-Ok ('удален ярлык ' + $path)
            } else {
                Show-Info ('ярлык не найден: ' + $path)
            }
        }

        $menuDir = Join-Path $StartMenuDir $menuFolderName
        if (Test-Path $menuDir) {
            Remove-Item -Path $menuDir -Recurse -Force
            Show-Ok ('удален каталог меню "Пуск": ' + $menuDir)
        } else {
            Show-Info ('каталог меню "Пуск" не найден: ' + $menuDir)
        }
    }

    Show-Head '3. Удаление каталога установки'
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Show-Ok ('удален каталог ' + $InstallDir)
    } else {
        Show-Info ('каталог не найден: ' + $InstallDir)
    }

    Show-Head 'Удаление завершено'
    Write-Host ''
    exit 0
} catch {
    Show-Err $_.Exception.Message
    Write-Host ''
    exit 1
}
