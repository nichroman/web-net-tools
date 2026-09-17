# ==========================================================================
#  Web_NetTools v0.0.2 - webnettools-common.ps1
#  Общие функции лаунчера: поиск Node.js, проверка порта и /api/health,
#  скрытый запуск сервера, остановка своих процессов, журнал, сообщения.
#
#  Файл не запускается самостоятельно, он подключается через точку:
#      . (Join-Path $launcherDir 'webnettools-common.ps1')
#
#  Совместимость: Windows PowerShell 2.0 (Windows 7) и PowerShell 7 (Windows 10/11).
#  Поэтому намеренно не используются: $PSScriptRoot, ConvertTo-Json,
#  Get-NetTCPConnection, Test-NetConnection, New-Object -Property.
# ==========================================================================

# Путь к node.exe: сначала стандартные каталоги установки, затем PATH
function Get-WebNetToolsNodeExe {
    $candidates = @()
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'nodejs\node.exe') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe') }
    if ($env:SystemDrive) { $candidates += (Join-Path $env:SystemDrive 'nodejs\node.exe') }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }

    $command = Get-Command 'node.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Definition }
    return $null
}

# Старшая цифра версии Node.js (например 24 для v24.19.0), -1 при ошибке
function Get-WebNetToolsNodeMajor {
    param([string]$NodeExe)
    try {
        $raw = & $NodeExe '-v' 2>$null
        if (-not $raw) { return -1 }
        $clean = ([string]$raw).Trim()
        if ($clean.StartsWith('v') -or $clean.StartsWith('V')) { $clean = $clean.Substring(1) }
        $parts = $clean.Split('.')
        return [int]$parts[0]
    } catch {
        return -1
    }
}

# Проверка TCP-подключения к порту
function Test-WebNetToolsTcpPort {
    param([string]$ComputerName = '127.0.0.1', [int]$Port = 80, [int]$TimeoutMs = 700)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

# HTTP GET с таймаутом; возвращает текст ответа или $null
function Get-WebNetToolsHttpText {
    param([string]$Url, [int]$TimeoutMs = 2000)
    $response = $null
    $reader = $null
    try {
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = 'GET'
        $request.Timeout = $TimeoutMs
        $request.Proxy = $null
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        return $reader.ReadToEnd()
    } catch {
        return $null
    } finally {
        if ($reader) { $reader.Close() }
        if ($response) { $response.Close() }
    }
}

# Быстрая проверка: есть ли на порту слушающий сокет (без попытки подключения,
# которая на закрытом порту может ждать весь таймаут)
function Test-WebNetToolsPortListening {
    param([int]$Port = 3000)
    try {
        $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        foreach ($listener in $listeners) {
            if ($listener.Port -eq $Port) { return $true }
        }
        return $false
    } catch {
        # урезанная среда .NET - откат к проверке подключением
        return (Test-WebNetToolsTcpPort -Port $Port -TimeoutMs 300)
    }
}

# Состояние порта: 'free' - свободен, 'ours' - работает наш сервер,
# 'busy' - порт занят посторонним приложением
function Get-WebNetToolsPortState {
    param([int]$Port = 3000, [string]$HealthMarker = '', [int]$TimeoutMs = 1500)
    if (-not (Test-WebNetToolsPortListening -Port $Port)) { return 'free' }
    if ($HealthMarker -ne '') {
        $text = Get-WebNetToolsHttpText -Url ('http://127.0.0.1:' + $Port + '/api/health') -TimeoutMs $TimeoutMs
        if ($text -and $text.IndexOf($HealthMarker) -ge 0) { return 'ours' }
    }
    return 'busy'
}

# Запись в журнал (UTF-8, ротация при размере более 1 МБ)
function Write-WebNetToolsLog {
    param([string]$LogFile = '', [string]$Message = '')
    if ($LogFile -eq '') { return }
    try {
        $dir = Split-Path -Parent $LogFile
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 1048576)) {
            Move-Item -Path $LogFile -Destination ($LogFile + '.old') -Force
        }
        $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] [' + $env:USERNAME + '] ' + $Message
        [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch {
        return
    }
}

# Диалоговое окно (не требует консоли)
function Show-WebNetToolsMessage {
    param([string]$Text = '', [string]$Title = 'Web_NetTools', [int]$Icon = 64, [int]$TimeoutSec = 0)
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.Popup($Text, $TimeoutSec, $Title, $Icon) | Out-Null
    } catch {
        Write-Host $Text
    }
}

# Открытие браузера на странице приложения
function Open-WebNetToolsBrowser {
    param([int]$Port = 3000, [string]$Path = '/')
    $url = 'http://localhost:' + $Port + $Path
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.Run($url, 1, $false)
    } catch {
        try { Start-Process $url } catch { Write-Host $url }
    }
}

# Сообщение пользователю: диалог либо только запись в журнал (ключ -NoDialogs
# нужен для автоматического запуска, когда диалог некому закрыть)
function Send-WebNetToolsNotice {
    param([string]$Text = '', [string]$LogFile = '', [int]$Icon = 64, [switch]$NoDialogs)
    if ($NoDialogs) {
        Write-WebNetToolsLog -LogFile $LogFile -Message ('сообщение: ' + $Text)
        Write-Host $Text
    } else {
        Show-WebNetToolsMessage -Icon $Icon -Text $Text
    }
}

# Остановка процесса вместе с дочерними (например cmd.exe -> node.exe)
function Stop-WebNetToolsProcessTree {
    param([int]$ProcessId = 0)
    if ($ProcessId -le 0) { return }
    $children = @()
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $children = @(Get-CimInstance -ClassName Win32_Process -Filter ('ParentProcessId=' + $ProcessId) -ErrorAction SilentlyContinue)
        } else {
            $children = @(Get-WmiObject -Class Win32_Process -Filter ('ParentProcessId=' + $ProcessId) -ErrorAction SilentlyContinue)
        }
    } catch {
        $children = @()
    }
    foreach ($child in $children) {
        Stop-WebNetToolsProcessTree -ProcessId ([int]$child.ProcessId)
    }
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
    } catch {
        return
    }
}

# Канонический (длинный) путь: убирает короткие имена вида PROGRA~1, чтобы
# сравнение с командной строкой процесса не зависело от формы записи пути
function Get-WebNetToolsLongPath {
    param([string]$Path = '')
    if ($Path -eq '') { return '' }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $Path) {
            $item = Get-Item -Path $Path -Force
            if ($item.PSIsContainer) { return $fso.GetFolder($Path).Path }
            return $fso.GetFile($Path).Path
        }
    } catch {
        return $Path
    }
    return $Path
}

# Короткий (8.3) путь: нужен, чтобы узнать процесс, запущенный по короткому пути
function Get-WebNetToolsShortPath {
    param([string]$Path = '')
    if ($Path -eq '') { return '' }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $Path) {
            $item = Get-Item -Path $Path -Force
            if ($item.PSIsContainer) { return $fso.GetFolder($Path).ShortPath }
            return $fso.GetFile($Path).ShortPath
        }
    } catch {
        return $Path
    }
    return $Path
}

# Командная строка процесса (нужна, чтобы не останавливать чужие процессы)
function Get-WebNetToolsProcessCommandLine {
    param([int]$ProcessId = 0)
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $process = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId=' + $ProcessId) -ErrorAction SilentlyContinue
            if ($process) { return $process.CommandLine }
        } else {
            $process = Get-WmiObject -Class Win32_Process -Filter ('ProcessId=' + $ProcessId) -ErrorAction SilentlyContinue
            if ($process) { return $process.CommandLine }
        }
    } catch {
        return $null
    }
    return $null
}

# Запуск сервера приложения: скрытый процесс node.exe + открытие браузера.
# Возвращает 0 - успех, 1 - ошибка, 2 - порт занят / сервер не ответил.
function Start-WebNetTool {
    param(
        [string]$Name = 'WEB_check_nodes',
        [string]$AppDir = '',
        [int]$Port = 3000,
        [string]$HealthMarker = 'WEB_check_nodes',
        [string]$LogFile = '',
        [int]$WaitSeconds = 20,
        [string]$BindAddress = '127.0.0.1',
        [switch]$NoBrowser,
        [switch]$NoDialogs
    )

    if ($LogFile -eq '') { $LogFile = Join-Path $env:TEMP 'webnettools-launcher.log' }

    if (($AppDir -eq '') -or (-not (Test-Path (Join-Path $AppDir 'server.js')))) {
        Write-WebNetToolsLog -LogFile $LogFile -Message ('ошибка: не найден server.js в каталоге "' + $AppDir + '"')
        Send-WebNetToolsNotice -Icon 16 -LogFile $LogFile -NoDialogs:$NoDialogs -Text ('Приложение не найдено:' + [Environment]::NewLine + $AppDir + [Environment]::NewLine + [Environment]::NewLine + 'Запустите install.bat из проекта Web_NetTools_v0.0.2.')
        return 1
    }

    # Канонический (длинный) путь: благодаря этому команда запуска и журнал
    # используют одну и ту же форму пути независимо от коротких имен 8.3
    $longAppDir = Get-WebNetToolsLongPath -Path $AppDir
    if ($longAppDir -ne '') { $AppDir = $longAppDir }

    $nodeExe = Get-WebNetToolsNodeExe
    if (-not $nodeExe) {
        Write-WebNetToolsLog -LogFile $LogFile -Message 'ошибка: Node.js не найден'
        Send-WebNetToolsNotice -Icon 16 -LogFile $LogFile -NoDialogs:$NoDialogs -Text ('Node.js не найден.' + [Environment]::NewLine + [Environment]::NewLine + 'Установите Node.js 14 или новее с https://nodejs.org' + [Environment]::NewLine + '(для Windows 7 x86: node-v14.21.3-x86.msi)')
        return 1
    }

    $nodeMajor = Get-WebNetToolsNodeMajor -NodeExe $nodeExe
    if (($nodeMajor -gt 0) -and ($nodeMajor -lt 13)) {
        Write-WebNetToolsLog -LogFile $LogFile -Message ('ошибка: устаревшая версия Node.js ' + $nodeMajor)
        Send-WebNetToolsNotice -Icon 16 -LogFile $LogFile -NoDialogs:$NoDialogs -Text ('Требуется Node.js 13 или новее, найдена версия ' + $nodeMajor + '.' + [Environment]::NewLine + 'Скачать: https://nodejs.org')
        return 1
    }

    $state = Get-WebNetToolsPortState -Port $Port -HealthMarker $HealthMarker
    if ($state -eq 'ours') {
        Write-WebNetToolsLog -LogFile $LogFile -Message ('сервер уже запущен (порт ' + $Port + '), открываю браузер')
        if (-not $NoBrowser) { Open-WebNetToolsBrowser -Port $Port }
        return 0
    }
    if ($state -eq 'busy') {
        Write-WebNetToolsLog -LogFile $LogFile -Message ('ошибка: порт ' + $Port + ' занят посторонним приложением')
        Send-WebNetToolsNotice -Icon 48 -LogFile $LogFile -NoDialogs:$NoDialogs -Text ('Порт ' + $Port + ' занят другим приложением.' + [Environment]::NewLine + [Environment]::NewLine + 'Закройте это приложение или запустите сервер вручную на другом порту:' + [Environment]::NewLine + 'set PORT=3002 && node server.js')
        return 2
    }

    # Порт и адрес прослушивания задаёт сам ярлык: они передаются запускаемому
    # процессу через переменные окружения, поэтому глобальные PORT/HOST на машине
    # не влияют на работу ярлыков.
    $env:PORT = [string]$Port
    if ($BindAddress -ne '') { $env:HOST = $BindAddress }

    $command = '/c ""' + $nodeExe + '" "' + (Join-Path $AppDir 'server.js') + '" >> "' + $LogFile + '" 2>&1"'
    $wrapperProcess = $null
    try {
        $wrapperProcess = Start-Process -FilePath $env:ComSpec -ArgumentList $command -WorkingDirectory $AppDir -WindowStyle Hidden -PassThru
    } catch {
        Write-WebNetToolsLog -LogFile $LogFile -Message ('ошибка запуска процесса: ' + $_.Exception.Message)
        Send-WebNetToolsNotice -Icon 16 -LogFile $LogFile -NoDialogs:$NoDialogs -Text ('Не удалось запустить сервер:' + [Environment]::NewLine + $_.Exception.Message)
        return 1
    }

    $portEnvNote = 'не задана'
    if ($env:PORT) { $portEnvNote = $env:PORT }
    $hostEnvNote = 'не задана'
    if ($env:HOST) { $hostEnvNote = $env:HOST }
    Write-WebNetToolsLog -LogFile $LogFile -Message ('запуск: ' + $Name + ', порт ' + $Port + ', адрес ' + $BindAddress + ', каталог ' + $AppDir + ', node ' + $nodeExe + ', PORT=' + $portEnvNote + ', HOST=' + $hostEnvNote)

    $ready = $false
    $exited = $false
    $attempts = [int](($WaitSeconds * 1000) / 400)
    for ($i = 0; $i -lt $attempts; $i++) {
        Start-Sleep -Milliseconds 400
        if ((Get-WebNetToolsPortState -Port $Port -HealthMarker $HealthMarker) -eq 'ours') {
            $ready = $true
            break
        }
        # если запущенный процесс уже завершился, ждать бессмысленно
        if ($wrapperProcess) {
            $wrapperProcess.Refresh()
            if ($wrapperProcess.HasExited) {
                $exited = $true
                break
            }
        }
    }

    if (-not $ready) {
        # сервер не поднялся - убираем запущенный процесс, чтобы не остался лишний экземпляр
        if ($wrapperProcess) { Stop-WebNetToolsProcessTree -ProcessId $wrapperProcess.Id }

        $portEnv = 'не задана'
        if ($env:PORT) { $portEnv = $env:PORT }
        $hostEnv = 'не задана'
        if ($env:HOST) { $hostEnv = $env:HOST }

        if ($exited) {
            $reason = 'Процесс сервера завершился сразу после запуска (обычно это занятый порт или ошибка в приложении).'
            Write-WebNetToolsLog -LogFile $LogFile -Message ('сервер завершился сразу после запуска (порт ' + $Port + ', адрес ' + $BindAddress + ')')
        } else {
            $reason = 'Сервер не ответил за ' + $WaitSeconds + ' секунд на порту ' + $Port + '.'
            Write-WebNetToolsLog -LogFile $LogFile -Message ('сервер не ответил за ' + $WaitSeconds + ' с (порт ' + $Port + ', адрес ' + $BindAddress + ')')
        }

        $message = $reason + [Environment]::NewLine + [Environment]::NewLine +
            'Проверьте журнал:' + [Environment]::NewLine + $LogFile + [Environment]::NewLine + [Environment]::NewLine +
            'Запуск выполнен со значениями: PORT=' + $portEnv + ', HOST=' + $hostEnv + [Environment]::NewLine +
            'Проверьте, не занят ли порт другой программой: netstat -ano | findstr :' + $Port

        Send-WebNetToolsNotice -Icon 48 -LogFile $LogFile -NoDialogs:$NoDialogs -Text $message
        return 2
    }

    Write-WebNetToolsLog -LogFile $LogFile -Message ('сервер готов: http://localhost:' + $Port)
    if (-not $NoBrowser) { Open-WebNetToolsBrowser -Port $Port }
    return 0
}

# Остановка серверов Web_NetTools по занятым портам (только свои процессы node.exe/cmd.exe).
# Возвращает массив строк с отчётом.
function Stop-WebNetToolProcess {
    param([int[]]$Ports = @(3000, 3001), [string]$AppRoot = '')

    $report = @()
    $processIds = @()
    $netstat = & netstat -ano -p TCP 2>$null

    # Каталог установки может быть записан длинным или коротким (8.3) путем,
    # поэтому процесс считается нашим, если его командная строка содержит любую форму
    $roots = @()
    if ($AppRoot -ne '') {
        $roots += $AppRoot
        $longRoot = Get-WebNetToolsLongPath -Path $AppRoot
        if (($longRoot -ne '') -and ($roots -notcontains $longRoot)) { $roots += $longRoot }
        $shortRoot = Get-WebNetToolsShortPath -Path $AppRoot
        if (($shortRoot -ne '') -and ($roots -notcontains $shortRoot)) { $roots += $shortRoot }
    }

    foreach ($line in $netstat) {
        if (([string]$line).IndexOf('TCP') -lt 0) { continue }
        $fields = @($line -split '\s+' | Where-Object { $_ -ne '' })
        if ($fields.Count -lt 5) { continue }
        $local = $fields[1]
        foreach ($port in $Ports) {
            if ($local -match (':' + $port + '$')) {
                $processIds += [int]$fields[$fields.Count - 1]
                break
            }
        }
    }

    $processIds = @($processIds | Sort-Object -Unique)

    if ($processIds.Count -eq 0) { return $report }

    foreach ($processId in $processIds) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        $name = $process.ProcessName

        if (($name -ne 'node') -and ($name -ne 'cmd')) {
            $report += ('порт занят посторонним процессом ' + $name + ' (PID ' + $processId + '), он не остановлен')
            continue
        }

        if ($roots.Count -gt 0) {
            $commandLine = Get-WebNetToolsProcessCommandLine -ProcessId $processId
            $owned = $false
            if ($commandLine) {
                foreach ($root in $roots) {
                    if ($commandLine.IndexOf($root, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $owned = $true
                        break
                    }
                }
            } else {
                # командную строку прочитать не удалось (процесс другого пользователя
                # без прав администратора) - считаем процесс своим по имени и порту
                $owned = $true
            }
            if (-not $owned) {
                $report += ('процесс ' + $name + ' (PID ' + $processId + ') запущен из другого каталога (другая установка) и не остановлен')
                continue
            }
        }

        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            $report += ('остановлен процесс ' + $name + ' (PID ' + $processId + ')')
        } catch {
            $report += ('не удалось остановить ' + $name + ' (PID ' + $processId + '): ' + $_.Exception.Message)
        }
    }

    return $report
}


