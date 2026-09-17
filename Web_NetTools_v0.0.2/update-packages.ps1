<#
    Web_NetTools v0.0.2 - update-packages.ps1
    Обновляет приложения в дистрибутиве: копирует актуальные каталоги утилит
    из проектов-источников в packages\check-nodes и packages\check-ports.

    Права администратора не нужны. Запуск:
        powershell -NoProfile -ExecutionPolicy Bypass -File update-packages.ps1
        powershell -NoProfile -ExecutionPolicy Bypass -File update-packages.ps1 -Force

    Параметры:
        -NodesSource  каталог WEB_check_nodes_* (по умолчанию ..\WEB_check_nodes_v0.0.4)
        -PortsSource  каталог WEB_check_ports_* (по умолчанию ..\WEB_check_ports_v0.0.1)
        -Force        обновлять без запроса подтверждения

    Из источников копируется всё содержимое, включая node_modules: дистрибутив
    остаётся самодостаточным (установка не требует npm и доступа в интернет).
    Исключаются служебные файлы: .git, .gitignore, logs, результаты сканирования.
#>

param(
    [string]$NodesSource = '',
    [string]$PortsSource = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptPath    = $MyInvocation.MyCommand.Definition
$projectDir    = Split-Path -Parent $scriptPath
$projectParent = Split-Path -Parent $projectDir
$packagesDir   = Join-Path $projectDir 'packages'

if ($NodesSource -eq '') { $NodesSource = Join-Path $projectParent 'WEB_check_nodes_v0.0.4' }
if ($PortsSource -eq '') { $PortsSource = Join-Path $projectParent 'WEB_check_ports_v0.0.1' }

function Show-Head([string]$Text) { Write-Host ''; Write-Host ('=== ' + $Text) -ForegroundColor Cyan }
function Show-Ok([string]$Text) { Write-Host ('  [ok] ' + $Text) -ForegroundColor Green }
function Show-Info([string]$Text) { Write-Host ('       ' + $Text) }
function Show-Warn([string]$Text) { Write-Host ('  [!] ' + $Text) -ForegroundColor Yellow }
function Show-Err([string]$Text) { Write-Host ('  [x] ' + $Text) -ForegroundColor Red }

function Copy-WebNetToolsApp {
    param([string]$Source, [string]$Destination, [string]$Title)

    if (-not (Test-Path (Join-Path $Source 'server.js'))) {
        throw ('Не найден server.js в каталоге ' + $Source + ' (' + $Title + ')')
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy $Source $Destination /E /COPY:DAT /XD '.git' 'logs' /XF '.gitignore' 'scan_results*.csv' 'Port*Opened.txt' 'Port*Closed.txt' /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ge 8) {
        throw ('robocopy: ошибка копирования ' + $Source + ' -> ' + $Destination + ' (код ' + $code + ')')
    }

    if (-not (Test-Path (Join-Path $Destination 'server.js'))) {
        throw ('После копирования не найден server.js в ' + $Destination)
    }
    if (-not (Test-Path (Join-Path $Destination 'node_modules'))) {
        Show-Warn ($Title + ': в источнике нет node_modules - перед установкой выполните npm install в каталоге ' + $Source)
    }

    $sum = (Get-ChildItem $Destination -Recurse -File | Measure-Object -Property Length -Sum)
    Show-Ok ($Title + ': ' + $sum.Count + ' файлов, ' + [math]::Round(($sum.Sum / 1MB), 2) + ' МБ -> ' + $Destination)
}

function Get-WebNetToolsAppVersion {
    param([string]$Path)
    $packageJson = Join-Path $Path 'package.json'
    if (-not (Test-Path $packageJson)) { return 'неизвестно' }
    try {
        $text = [System.IO.File]::ReadAllText($packageJson)
        $match = [regex]::Match($text, '"version"\s*:\s*"([^"]+)"')
        if ($match.Success) { return $match.Groups[1].Value }
    } catch {
        return 'неизвестно'
    }
    return 'неизвестно'
}

# ==== Основной сценарий ====================================================

Show-Head 'Web_NetTools v0.0.2 - обновление приложений в дистрибутиве'
Show-Info ('Источник (узлы) : ' + $NodesSource)
Show-Info ('Источник (порты): ' + $PortsSource)
Show-Info ('Дистрибутив     : ' + $packagesDir)

try {
    $alreadyExists = (Test-Path (Join-Path $packagesDir 'check-nodes')) -or (Test-Path (Join-Path $packagesDir 'check-ports'))

    if ($alreadyExists -and (-not $Force)) {
        Write-Host ''
        $answer = Read-Host 'Каталоги приложений в packages уже есть. Перезаписать их? Введите yes для продолжения'
        if ($answer -ne 'yes') {
            Show-Info 'Отменено пользователем'
            exit 1
        }
    }

    Copy-WebNetToolsApp -Source $NodesSource -Destination (Join-Path $packagesDir 'check-nodes') -Title 'проверка узлов'
    Copy-WebNetToolsApp -Source $PortsSource -Destination (Join-Path $packagesDir 'check-ports') -Title 'проверка портов'

    # Фиксируем состав дистрибутива: что и когда скопировано
    $lines = @()
    $lines += 'Дистрибутив Web_NetTools v0.0.2 - состав каталога packages'
    $lines += 'Обновлено: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $lines += 'check-nodes <- ' + $NodesSource
    $lines += '  версия package.json: ' + (Get-WebNetToolsAppVersion -Path (Join-Path $packagesDir 'check-nodes'))
    $lines += 'check-ports <- ' + $PortsSource
    $lines += '  версия package.json: ' + (Get-WebNetToolsAppVersion -Path (Join-Path $packagesDir 'check-ports'))

    $versionFile = Join-Path $packagesDir 'VERSION.txt'
    [System.IO.File]::WriteAllText($versionFile, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    Show-Ok ('состав зафиксирован: ' + $versionFile)

    Show-Head 'Готово'
    Show-Info 'Установка на компьютер: install.bat (ярлыки для всех пользователей)'
    exit 0
} catch {
    Show-Err $_.Exception.Message
    Write-Host ''
    exit 1
}
