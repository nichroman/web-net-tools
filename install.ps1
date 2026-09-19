<#
    Web_NetTools v0.0.2 - install.ps1
    Установка WEB_check_nodes_v0.0.4 и WEB_check_ports_v0.0.1 в ОС Windows так,
    чтобы программы были доступны ВСЕМ пользователям через ярлыки на общем
    рабочем столе (C:\Users\Public\Desktop) и в общем меню "Пуск".

    Запуск (нужны права администратора):
        install.bat                          - двойной клик, UAC запрашивается сам
        powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

    Откуда берутся программы (ищутся по маркеру в server.js):
        1) параметр -NodesSource / -PortsSource;
        2) <проект установщика>\packages\check-nodes и packages\check-ports
           (рекомендуется: положите туда каталоги программ, чтобы установщик
           был самодостаточным и не зависел от профиля пользователя);
        3) каталог установщика и соседние с ним каталоги (в том числе вложенные);
        4) общие и пользовательские папки: C:\Users\Public\Desktop, Desktop,
           Downloads, Documents, C:\distr, C:\Tools.

    Параметры:
        -InstallDir     каталог установки         (по умолчанию C:\Tools\WebNetTools)
        -NodesSource    каталог с WEB_check_nodes (по умолчанию автоопределение)
        -PortsSource    каталог с WEB_check_ports (по умолчанию автоопределение)
        -PackagesDir    каталог с готовыми пакетами программ
                        (по умолчанию <проект установщика>\packages)
        -DesktopDir     каталог для ярлыков всех пользователей
        -StartMenuDir   каталог общего меню "Пуск" (программы)
        -SkipAcl        не выдавать права группе "Пользователи"
        -SkipShortcuts  не создавать ярлыки
        -SkipStop       не останавливать запущенные серверы перед копированием
        -SkipSearch     не искать в общих и пользовательских папках (только параметр,
                        packages, каталог установщика и соседние каталоги)

    Схема размещения описана в README.md проекта Web_NetTools_v0.0.2.
#>

param(
    [string]$InstallDir = 'C:\Tools\WebNetTools',
    [string]$NodesSource = '',
    [string]$PortsSource = '',
    [string]$PackagesDir = '',
    [string]$DesktopDir = '',
    [string]$StartMenuDir = '',
    [switch]$SkipAcl,
    [switch]$SkipShortcuts,
    [switch]$SkipStop,
    [switch]$SkipSearch
)

$ErrorActionPreference = 'Stop'

$scriptPath     = $MyInvocation.MyCommand.Definition
$projectDir     = Split-Path -Parent $scriptPath
$projectParent  = Split-Path -Parent $projectDir
$launcherSource = Join-Path $projectDir 'launcher'

$nodesDirName    = 'check-nodes'
$portsDirName    = 'check-ports'
$logsDirName     = 'logs'
$launcherDirName = 'launcher'
$menuFolderName  = 'Web_NetTools'
$packagesDirName = 'packages'

$appNodesMarker = 'WEB_check_nodes'
$appPortsMarker = 'WEB_check_ports'
$portNodes = 3000
$portPorts = 3001
$shortcutNodesName = 'Проверка узлов (Web_NetTools)'
$shortcutPortsName = 'Проверка портов (Web_NetTools)'
$shortcutStopName  = 'Остановить серверы Web_NetTools'

if ($NodesSource -eq '') { $NodesSource = Join-Path $projectParent 'WEB_check_nodes_v0.0.4' }
if ($PortsSource -eq '') { $PortsSource = Join-Path $projectParent 'WEB_check_ports_v0.0.1' }
if ($PackagesDir -eq '') { $PackagesDir = Join-Path $projectDir $packagesDirName }
if ($DesktopDir -eq '') { $DesktopDir = [Environment]::GetFolderPath('CommonDesktopDirectory') }
if ($StartMenuDir -eq '') {
    $StartMenuDir = Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) 'Programs'
}

function Show-Head([string]$Text) { Write-Host ''; Write-Host ('=== ' + $Text) -ForegroundColor Cyan }
function Show-Ok([string]$Text) { Write-Host ('  [ok] ' + $Text) -ForegroundColor Green }
function Show-Info([string]$Text) { Write-Host ('       ' + $Text) }
function Show-Warn([string]$Text) { Write-Host ('  [!] ' + $Text) -ForegroundColor Yellow }
function Show-Err([string]$Text) { Write-Host ('  [x] ' + $Text) -ForegroundColor Red }

function Test-WebNetToolsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Copy-WebNetToolsTree {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    # /COPY:DAT - копируются данные, атрибуты и время, но не права доступа:
    # файлы в каталоге установки наследуют его ACL, а не права исходного профиля
    & robocopy $Source $Destination /E /COPY:DAT /XD '.git' /XF '.gitignore' /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ge 8) {
        throw ('robocopy: ошибка копирования ' + $Source + ' -> ' + $Destination + ' (код ' + $code + ')')
    }
}

# --- поиск каталогов с программами ---------------------------------------

# Тип приложения определяется по содержимому server.js, а не по имени каталога.
# Сначала проверяются уникальные маркеры сканера портов: в его комментариях
# упоминается "WEB_check_nodes", поэтому порядок проверок важен.
function Get-WebNetToolsAppKind {
    param([string]$Path = '')
    $serverJs = Join-Path $Path 'server.js'
    if (-not (Test-Path $serverJs)) { return '' }
    try {
        $text = [System.IO.File]::ReadAllText($serverJs)
    } catch {
        return ''
    }
    if (($text.IndexOf('/api/scan') -ge 0) -or ($text.IndexOf("'WEB_check_ports'") -ge 0) -or ($text.IndexOf('STATUS_OPEN') -ge 0)) { return 'ports' }
    if (($text.IndexOf('/api/ping') -ge 0) -or ($text.IndexOf('ping -n ') -ge 0) -or ($text.IndexOf("'WEB_check_nodes'") -ge 0)) { return 'nodes' }
    return ''
}

# Ищет каталог приложения: сначала сам путь, затем вложенные подкаталоги
# (архивы часто распаковываются как WEB_check_nodes_v0.0.4\WEB_check_nodes_v0.0.4)
function Find-WebNetToolsAppDir {
    param([string]$Path = '', [string]$Kind = 'nodes', [int]$Depth = 2)
    if (($Path -eq '') -or (-not (Test-Path $Path))) { return '' }
    if ((Get-WebNetToolsAppKind -Path $Path) -eq $Kind) { return (Get-WebNetToolsLongPath -Path $Path) }
    if ($Depth -le 0) { return '' }

    $subDirectories = @()
    try {
        $subDirectories = @(Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue)
    } catch {
        $subDirectories = @()
    }

    foreach ($subDirectory in $subDirectories) {
        if ($subDirectory.Name -match '^(\.|node_modules$|logs$|launcher$|packages$|webnettools)' -or $subDirectory.Name -match '^\.') { continue }
        $found = Find-WebNetToolsAppDir -Path $subDirectory.FullName -Kind $Kind -Depth ($Depth - 1)
        if ($found -ne '') { return $found }
    }
    return ''
}

# Краткое содержимое каталога - для понятного сообщения об ошибке
function Get-WebNetToolsDirSummary {
    param([string]$Path = '')
    if (($Path -eq '') -or (-not (Test-Path $Path))) { return 'каталог не найден' }
    try {
        $items = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 10)
        if ($items.Count -eq 0) { return 'каталог пуст' }
        $names = @()
        foreach ($item in $items) { $names += $item.Name }
        return ('в каталоге: ' + ($names -join ', '))
    } catch {
        return 'не удалось прочитать каталог'
    }
}

# Последовательный поиск каталога программы по плану поиска.
# Возвращает хэш-таблицу: Found - найденный путь, Checked - что проверено и найдено.
function Resolve-WebNetToolsSource {
    param(
        [string]$Kind = 'nodes',
        [string]$ExplicitPath = '',
        [string]$PackagesDir = '',
        [string]$ExcludePath = '',
        [array]$SearchPlan = @()
    )

    $checked = @()
    $plan = @()

    if ($ExplicitPath -ne '') {
        $plan += @{ Path = $ExplicitPath; Depth = 3; Title = 'параметр -NodesSource/-PortsSource' }
    }
    if ($PackagesDir -ne '') {
        $plan += @{ Path = $PackagesDir; Depth = 2; Title = 'каталог packages установщика' }
    }
    foreach ($item in $SearchPlan) { $plan += $item }

    foreach ($item in $plan) {
        $path = $item['Path']
        $depth = 2
        if ($item.ContainsKey('Depth')) { $depth = $item['Depth'] }
        $title = ''
        if ($item.ContainsKey('Title')) { $title = $item['Title'] }

        if (($path -eq '') -or (-not (Test-Path $path))) {
            $checked += ('  ' + $path + ' - не найден (' + $title + ')')
            continue
        }

        $found = Find-WebNetToolsAppDir -Path $path -Kind $Kind -Depth $depth
        if ($found -ne '') {
            # нельзя брать в качестве источника сам каталог установки (иначе копирование в себя)
            if (($ExcludePath -ne '') -and ($found.Length -ge $ExcludePath.Length) -and
                ($found.Substring(0, $ExcludePath.Length).ToLower() -eq $ExcludePath.ToLower())) {
                $checked += ('  ' + $found + ' - это каталог установки, пропущен (' + $title + ')')
                continue
            }
            return @{ Found = $found; Checked = $checked; FoundTitle = $title }
        }
        $checked += ('  ' + $path + ' - server.js не найден, ' + (Get-WebNetToolsDirSummary -Path $path) + ' (' + $title + ')')
    }

    return @{ Found = ''; Checked = $checked; FoundTitle = '' }
}

# --- иконка ярлыков -------------------------------------------------------

function Test-WebNetToolsIcon {
    param([string]$IconPath)
    if (-not (Test-Path $IconPath)) { return $false }
    try {
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Drawing.Icon -ArgumentList $IconPath
        $icon.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Convert-WebNetToolsPngToIcon {
    param([string]$PngPath, [string]$IconPath)
    try {
        Add-Type -AssemblyName System.Drawing
        $image = [System.Drawing.Image]::FromFile($PngPath)
        $bitmap = New-Object System.Drawing.Bitmap -ArgumentList @($image, 32, 32)
        $handle = $bitmap.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($handle)
        $stream = [System.IO.File]::Create($IconPath)
        $icon.Save($stream)
        $stream.Close()
        $icon.Dispose()
        $bitmap.Dispose()
        $image.Dispose()
        return (Test-WebNetToolsIcon -IconPath $IconPath)
    } catch {
        return $false
    }
}

# Подготавливает иконку для конкретного типа ярлыка:
#   - копирует .ico из каталога приложения/установщика, при отсутствии - конвертирует PNG.
# Возвращает путь к готовой иконке или "" (тогда ярлык создается со стандартной иконкой).
function Install-WebNetToolsAppIcon {
    param(
        [string]$InstallRoot = '',
        [string]$SourceDir = '',
        [string]$IconName = 'webnettools.ico',
        [string[]]$IconCandidates = @(),
        [string]$PngFallback = ''
    )
    $iconTarget = Join-Path (Join-Path $InstallRoot $launcherDirName) $IconName

    foreach ($candidate in $IconCandidates) {
        $source = Join-Path $SourceDir $candidate
        if (Test-Path $source) {
            Copy-Item -Path $source -Destination $iconTarget -Force
            if (Test-WebNetToolsIcon -IconPath $iconTarget) { return $iconTarget }
            Show-Warn ('Не удалось прочитать иконку ' + $source)
        }
    }

    if ($PngFallback -ne '') {
        $png = Join-Path $SourceDir $PngFallback
        if ((Test-Path $png) -and (Convert-WebNetToolsPngToIcon -PngPath $png -IconPath $iconTarget)) {
            return $iconTarget
        }
    }

    Show-Warn ('Иконка ' + $IconName + ' не найдена в ' + $SourceDir)
    return ''
}

# --- ярлыки ---------------------------------------------------------------

function New-WebNetToolsShortcut {
    param(
        [string]$Path,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation,
        [string]$Description
    )
    $shell = New-Object -ComObject WScript.Shell
    if (Test-Path $Path) { Remove-Item -Path $Path -Force }
    $link = $shell.CreateShortcut($Path)
    $link.TargetPath = $TargetPath
    $link.Arguments = $Arguments
    if ($WorkingDirectory -ne '') { $link.WorkingDirectory = $WorkingDirectory }
    if ($IconLocation -ne '') { $link.IconLocation = $IconLocation }
    if ($Description -ne '') { $link.Description = $Description }
    $link.WindowStyle = 7
    $link.Save()
}

# Интерпретатор для ярлыков: Windows PowerShell -> PowerShell 7 -> пустая строка
function Get-WebNetToolsLauncherTarget {
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $windowsPowerShell) { return $windowsPowerShell }
    $pwsh = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Definition }
    return ''
}

# --- инструкция в каталоге установки --------------------------------------

function Write-WebNetToolsInstallInfo {
    param([string]$InstallRoot, [string]$NodePath, [string]$NodeVersion, [string]$LauncherTarget, [string]$NodesSource, [string]$PortsSource)
    $lines = @()
    $lines += '=================================================================='
    $lines += ' Web_NetTools v0.0.2 - установка для всех пользователей Windows'
    $lines += '=================================================================='
    $lines += 'Дата установки : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $lines += 'Каталог        : ' + $InstallRoot
    $lines += 'Node.js        : ' + $NodePath + ' (' + $NodeVersion + ')'
    $lines += 'Интерпретатор  : ' + $LauncherTarget
    $lines += 'Источник (узлы): ' + $NodesSource
    $lines += 'Источник (порты): ' + $PortsSource
    $lines += ''
    $lines += 'СОСТАВ'
    $lines += '  check-nodes - WEB_check_nodes v0.0.4 - проверка узлов (ping), порт 3000'
    $lines += '  check-ports - WEB_check_ports v0.0.1 - сканер TCP-портов, порт 3001'
    $lines += '  launcher    - скрипты запуска (PowerShell и резервный VBScript)'
    $lines += '  logs        - журналы запуска и работы серверов'
    $lines += ''
    $lines += 'ЗАПУСК'
    $lines += '  Ярлыки "Проверка узлов (Web_NetTools)" и "Проверка портов (Web_NetTools)"'
    $lines += '  находятся на общем рабочем столе и в меню "Пуск" \ Web_NetTools.'
    $lines += '  Ярлык проверяет, запущен ли сервер, при необходимости запускает его скрыто'
    $lines += '  и открывает браузер (http://localhost:3000 или http://localhost:3001).'
    $lines += '  Пока сервер запущен, второго экземпляра не создается.'
    $lines += ''
    $lines += 'ВРУЧНУЮ (диагностика)'
    $lines += '  node "' + $InstallRoot + '\check-nodes\server.js"'
    $lines += '  node "' + $InstallRoot + '\check-ports\server.js"'
    $lines += '  Остановка: ярлык "Остановить серверы Web_NetTools" в меню "Пуск".'
    $lines += ''
    $lines += 'ДАННЫЕ'
    $lines += '  Наборы узлов (CSV/TXT) находятся в каталогах check-nodes и check-ports.'
    $lines += '  Группе "Пользователи" выданы права на изменение, поэтому новые списки и'
    $lines += '  результаты сканирования сохраняются без прав администратора.'
    $lines += '  ВАЖНО: списки узлов и результаты - общие для всех пользователей компьютера.'
    $lines += ''
    $lines += 'СЕТЬ И БРАНДМАУЭР'
    $lines += '  Серверы слушают только 127.0.0.1: доступны с этого компьютера и не вызывают'
    $lines += '  запрос брандмауэра. Для доступа с других ПК нужен запуск с HOST=0.0.0.0 и'
    $lines += '  разрешающее правило брандмауэра для портов 3000/3001.'
    $lines += ''
    $lines += 'ОБНОВЛЕНИЕ'
    $lines += '  1) Остановите серверы (ярлык в меню "Пуск").'
    $lines += '  2) Запустите install.bat из проекта новой версии - файлы перезапишутся,'
    $lines += '     ярлыки будут пересозданы. CSV-файлы сохраняются, но лучше иметь копию.'
    $lines += ''
    $lines += 'УДАЛЕНИЕ'
    $lines += '  Запустите uninstall.bat (права администратора).'

    $text = ($lines -join "`r`n") + "`r`n"
    $target = Join-Path $InstallRoot 'INSTALL.txt'
    [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($true)))
}

# ==========================================================================
#  Основной сценарий установки
# ==========================================================================

Show-Head 'Web_NetTools v0.0.2 - установка'
Show-Info ('Каталог установки : ' + $InstallDir)
Show-Info ('Проверка узлов    : ' + $NodesSource)
Show-Info ('Проверка портов   : ' + $PortsSource)
Show-Info ('Рабочий стол      : ' + $DesktopDir)
Show-Info ('Меню "Пуск"       : ' + $StartMenuDir)

try {
    # Общие функции лаунчера (поиск Node.js, канонические пути, журнал, остановка)
    . (Join-Path $launcherSource 'webnettools-common.ps1')

    # --- 1. права и окружение ---------------------------------------------
    Show-Head 'Проверка прав и окружения'
    if (-not (Test-WebNetToolsAdmin)) {
        if (-not $SkipAcl) {
            throw 'Нужны права администратора. Запустите install.bat (двойной клик) или: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 (для тестового запуска без администратора добавьте -SkipAcl)'
        }
        Show-Warn 'Работа без прав администратора: права доступа не настраиваются (-SkipAcl)'
    } else {
        Show-Ok 'Права администратора получены'
    }

    # --- 2. поиск каталогов с программами ---------------------------------
    # План поиска: параметр -> packages -> каталог установщика и соседние каталоги ->
    # общие и пользовательские папки. В каждом каталоге проверяются и вложенные папки.
    $searchPlan = @()
    $searchPlan += @{ Path = $projectDir; Depth = 2; Title = 'каталог установщика' }
    $searchPlan += @{ Path = $projectParent; Depth = 2; Title = 'каталог рядом с установщиком' }

    $searchLocations = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:PUBLIC 'Desktop'),
        (Join-Path $env:PUBLIC 'Documents'),
        'C:\distr',
        'C:\Tools'
    )
    if (-not $SkipSearch) {
        foreach ($location in $searchLocations) {
            $searchPlan += @{ Path = $location; Depth = 1; Title = 'поиск по известным местам' }
        }
    }

    $nodesExplicit = $NodesSource
    $portsExplicit = $PortsSource

    $nodesResolved = Resolve-WebNetToolsSource -Kind 'nodes' -ExplicitPath $nodesExplicit -PackagesDir $PackagesDir -ExcludePath $InstallDir -SearchPlan $searchPlan
    $NodesSource = $nodesResolved['Found']
    if ($NodesSource -eq '') {
        $lines = @()
        $lines += 'Не найден каталог программы "проверка узлов" (WEB_check_nodes): ни в одном месте нет server.js.'
        $lines += ''
        $lines += 'Проверено:'
        $lines += $nodesResolved['Checked']
        $lines += ''
        $lines += 'Как исправить (любой вариант):'
        $lines += '  1) скопируйте каталог WEB_check_nodes_v0.0.4 (внутри должен быть server.js) в'
        $lines += '     "' + (Join-Path $PackagesDir $nodesDirName) + '" - установщик станет самодостаточным;'
        $lines += '  2) запустите: install.bat -NodesSource "полный путь к каталогу, где лежит server.js";'
        $lines += '  3) положите каталог WEB_check_nodes_v0.0.4 рядом с каталогом Web_NetTools_v0.0.2.'
        throw ($lines -join [Environment]::NewLine)
    }

    $portsResolved = Resolve-WebNetToolsSource -Kind 'ports' -ExplicitPath $portsExplicit -PackagesDir $PackagesDir -ExcludePath $InstallDir -SearchPlan $searchPlan
    $PortsSource = $portsResolved['Found']
    if ($PortsSource -eq '') {
        $lines = @()
        $lines += 'Не найден каталог программы "проверка портов" (WEB_check_ports): ни в одном месте нет server.js.'
        $lines += ''
        $lines += 'Проверено:'
        $lines += $portsResolved['Checked']
        $lines += ''
        $lines += 'Как исправить (любой вариант):'
        $lines += '  1) скопируйте каталог WEB_check_ports_v0.0.1 (внутри должен быть server.js) в'
        $lines += '     "' + (Join-Path $PackagesDir $portsDirName) + '" - установщик станет самодостаточным;'
        $lines += '  2) запустите: install.bat -PortsSource "полный путь к каталогу, где лежит server.js";'
        $lines += '  3) положите каталог WEB_check_ports_v0.0.1 рядом с каталогом Web_NetTools_v0.0.2.'
        throw ($lines -join [Environment]::NewLine)
    }

    Show-Ok ('Проверка узлов: ' + $NodesSource)
    Show-Ok ('Проверка портов: ' + $PortsSource)

    foreach ($resolved in @($nodesResolved, $portsResolved)) {
        if ($resolved['FoundTitle'] -eq 'поиск по известным местам') {
            Show-Warn ('Каталог ' + $resolved['Found'] + ' найден поиском в общих/пользовательских папках - проверьте, что это нужная версия, или укажите каталог явно (-NodesSource/-PortsSource)')
        }
    }

    foreach ($source in @($NodesSource, $PortsSource)) {
        if (-not (Test-Path (Join-Path $source 'node_modules'))) {
            Show-Warn ('В каталоге ' + $source + ' нет node_modules - в приложении не выполнен npm install')
        }
        if (($source -match '(?i)\\users\\') -and ($source -notmatch '(?i)\\users\\public\\')) {
            Show-Warn ('Источник в профиле пользователя (' + $source + '): установка в ' + $InstallDir + ' будет доступна всем пользователям, но для переноса на другие ПК положите каталоги в ' + $PackagesDir)
        }
    }

    # --- 3. Node.js -------------------------------------------------------
    $nodeExe = Get-WebNetToolsNodeExe
    $nodeVersion = 'не найден'
    if ($nodeExe) {
        $rawVersion = & $nodeExe '-v'
        $nodeVersion = ([string]$rawVersion).Trim()
        if ((Get-WebNetToolsNodeMajor -NodeExe $nodeExe) -lt 13) {
            Show-Warn ('Node.js ' + $nodeVersion + ' устарел, требуется 13 или новее')
        } else {
            Show-Ok ('Node.js ' + $nodeVersion + ' (' + $nodeExe + ')')
        }
    } else {
        Show-Warn 'Node.js не найден. Установите Node.js 14+ (для Windows 7 x86 - node-v14.21.3-x86.msi) с https://nodejs.org'
    }

    # --- 4. остановка запущенных серверов ---------------------------------
    if (-not $SkipStop) {
        Show-Head 'Остановка запущенных серверов'
        $stopped = Stop-WebNetToolProcess -Ports @($portNodes, $portPorts) -AppRoot $InstallDir
        if ($stopped.Count -eq 0) {
            Show-Info 'Запущенные серверы не найдены'
        } else {
            foreach ($item in $stopped) { Show-Info $item }
        }
    }

    # --- 5. копирование файлов --------------------------------------------
    Show-Head 'Копирование программ'
    $nodesTarget = Join-Path $InstallDir $nodesDirName
    $portsTarget = Join-Path $InstallDir $portsDirName
    Copy-WebNetToolsTree -Source $NodesSource -Destination $nodesTarget
    Show-Ok ($nodesDirName + ' <- ' + $NodesSource)
    Copy-WebNetToolsTree -Source $PortsSource -Destination $portsTarget
    Show-Ok ($portsDirName + ' <- ' + $PortsSource)
    Copy-WebNetToolsTree -Source $launcherSource -Destination (Join-Path $InstallDir $launcherDirName)
    Show-Ok ($launcherDirName + ' <- ' + $launcherSource)
    New-Item -ItemType Directory -Path (Join-Path $InstallDir $logsDirName) -Force | Out-Null
    Show-Ok ('логи: ' + (Join-Path $InstallDir $logsDirName))

    # Проверка результата копирования: без server.js приложение не запустится
    $installedApps = @(
        @{ Title = 'проверка узлов'; Path = $nodesTarget },
        @{ Title = 'проверка портов'; Path = $portsTarget }
    )
    foreach ($installed in $installedApps) {
        if (-not (Test-Path (Join-Path $installed['Path'] 'server.js'))) {
            throw ('После копирования не найден server.js в ' + $installed['Path'] + ' (' + $installed['Title'] + ')')
        }
        if (-not (Test-Path (Join-Path $installed['Path'] 'index.html'))) {
            Show-Warn ('В ' + $installed['Path'] + ' нет index.html - интерфейс не откроется')
        }
        if (-not (Test-Path (Join-Path $installed['Path'] 'node_modules'))) {
            Show-Warn ('В ' + $installed['Path'] + ' нет node_modules - выполните npm install в каталоге-источнике и повторите установку')
        }
    }
    Show-Ok 'Состав программ проверен (server.js на месте)'

    # --- 6. права доступа для всех пользователей --------------------------
    if (-not $SkipAcl) {
        Show-Head 'Права доступа для всех пользователей'
        & icacls $InstallDir /grant '*S-1-5-32-545:(OI)(CI)M' /T /C /Q | Out-Null
        $aclCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($aclCode -eq 0) {
            Show-Ok 'Группе "Пользователи" выдано право "Изменение" (нужно для сохранения результатов сканирования)'
        } else {
            Show-Warn ('icacls завершился с кодом ' + $aclCode)
        }
    }

    # --- 7. иконки --------------------------------------------------------
    # Ярлыки приложений получают собственные иконки:
    #   проверка узлов - webnettools_PingNode.ico, проверка портов - webnettools_PortScan.ico,
    #   общая иконка (остановка серверов) - webnettools.ico.
    Show-Head 'Подготовка иконок'
    $iconNodes = Install-WebNetToolsAppIcon -InstallRoot $InstallDir -SourceDir $projectDir -IconName 'webnettools_PingNode.ico' -IconCandidates @('webnettools_PingNode.ico') -PngFallback ''
    $iconPorts = Install-WebNetToolsAppIcon -InstallRoot $InstallDir -SourceDir $projectDir -IconName 'webnettools_PortScan.ico' -IconCandidates @('webnettools_PortScan.ico') -PngFallback ''
    $iconCommon = Install-WebNetToolsAppIcon -InstallRoot $InstallDir -SourceDir $NodesSource -IconName 'webnettools.ico' -IconCandidates @('monkey.ico', 'favicon.ico') -PngFallback 'monkey.png'

    if ($iconNodes -ne '') { Show-Ok ('Иконка проверки узлов: ' + $iconNodes) } else { $iconNodes = $iconCommon }
    if ($iconPorts -ne '') { Show-Ok ('Иконка проверки портов: ' + $iconPorts) } else { $iconPorts = $iconCommon }
    if ($iconCommon -ne '') { Show-Ok ('Общая иконка         : ' + $iconCommon) }
    if (($iconNodes -eq '') -and ($iconPorts -eq '') -and ($iconCommon -eq '')) {
        Show-Warn 'Иконки не найдены, ярлыки будут созданы со стандартной иконкой Windows'
    }

    # --- 8. ярлыки --------------------------------------------------------
    if (-not $SkipShortcuts) {
        Show-Head 'Ярлыки на общем рабочем столе и в меню "Пуск"'

        $launcherTarget = Get-WebNetToolsLauncherTarget
        $useFallback = $false
        if ($launcherTarget -eq '') {
            Show-Warn 'powershell.exe/pwsh.exe не найдены - используются резервные VBScript-ярлыки'
            $launcherTarget = Join-Path $env:SystemRoot 'System32\wscript.exe'
            $useFallback = $true
        }

        if ($useFallback) {
            $nodesArguments = '"' + (Join-Path $InstallDir 'launcher\fallback\start-check-nodes.vbs') + '"'
            $portsArguments = '"' + (Join-Path $InstallDir 'launcher\fallback\start-check-ports.vbs') + '"'
            $stopTarget = ''
            $stopArguments = ''
        } else {
            $nodesArguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'launcher\start-check-nodes.ps1') + '"'
            $portsArguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'launcher\start-check-ports.ps1') + '"'
            $stopTarget = $launcherTarget
            $stopArguments = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "' + (Join-Path $InstallDir 'launcher\stop-webnettools.ps1') + '"'
        }

        New-Item -ItemType Directory -Path $DesktopDir -Force | Out-Null
        New-Item -ItemType Directory -Path $StartMenuDir -Force | Out-Null

        New-WebNetToolsShortcut -Path (Join-Path $DesktopDir ($shortcutNodesName + '.lnk')) `
            -TargetPath $launcherTarget -Arguments $nodesArguments -WorkingDirectory $nodesTarget `
            -IconLocation $iconNodes -Description 'Проверка доступности сетевых узлов (WEB_check_nodes v0.0.4)'
        New-WebNetToolsShortcut -Path (Join-Path $DesktopDir ($shortcutPortsName + '.lnk')) `
            -TargetPath $launcherTarget -Arguments $portsArguments -WorkingDirectory $portsTarget `
            -IconLocation $iconPorts -Description 'Сканер TCP-портов (WEB_check_ports v0.0.1)'
        Show-Ok ('Рабочий стол: ' + $shortcutNodesName + '.lnk')
        Show-Ok ('Рабочий стол: ' + $shortcutPortsName + '.lnk')

        $menuDir = Join-Path $StartMenuDir $menuFolderName
        New-Item -ItemType Directory -Path $menuDir -Force | Out-Null
        New-WebNetToolsShortcut -Path (Join-Path $menuDir 'Проверка узлов.lnk') `
            -TargetPath $launcherTarget -Arguments $nodesArguments -WorkingDirectory $nodesTarget `
            -IconLocation $iconNodes -Description 'Проверка доступности сетевых узлов'
        New-WebNetToolsShortcut -Path (Join-Path $menuDir 'Проверка портов.lnk') `
            -TargetPath $launcherTarget -Arguments $portsArguments -WorkingDirectory $portsTarget `
            -IconLocation $iconPorts -Description 'Сканер TCP-портов'
        if (-not $useFallback) {
            New-WebNetToolsShortcut -Path (Join-Path $menuDir ($shortcutStopName + '.lnk')) `
                -TargetPath $stopTarget -Arguments $stopArguments -WorkingDirectory $InstallDir `
                -IconLocation $iconCommon -Description 'Остановка серверов Web_NetTools'
        }
        Show-Ok ('Меню "Пуск": ' + $menuDir)
    }

    # --- 9. инструкция в каталоге установки -------------------------------
    Write-WebNetToolsInstallInfo -InstallRoot $InstallDir -NodePath $nodeExe -NodeVersion $nodeVersion `
        -LauncherTarget (Get-WebNetToolsLauncherTarget) -NodesSource $NodesSource -PortsSource $PortsSource
    Show-Ok ('Инструкция: ' + (Join-Path $InstallDir 'INSTALL.txt'))

    # --- 10. итог ---------------------------------------------------------
    Show-Head 'Установка завершена'
    Show-Info ('Каталог            : ' + $InstallDir)
    Show-Info 'Проверка узлов     : ярлык на рабочем столе -> http://localhost:3000'
    Show-Info 'Проверка портов    : ярлык на рабочем столе -> http://localhost:3001'
    Show-Info ('Журналы            : ' + (Join-Path $InstallDir $logsDirName))
    Show-Info 'Остановка серверов : меню "Пуск" \ Web_NetTools'
    Write-Host ''
    exit 0
} catch {
    Show-Err $_.Exception.Message
    Write-Host ''
    exit 1
}

