// WEB_check_ports_v0.0.1
// Веб-версия сканера TCP-портов (аналог port_scanner.ps1 / port443_scanner.ps1 из проекта PortScaner).
// CSV-результат полностью повторяет формат PowerShell-версии: Hostname,Port,Status,ScanTime
// Сервер: Node.js + Express 4.17.3 (как в WEB_check_nodes_v0.0.4), клиент: ES5 (совместимость с IE11).

var express = require('express');
var cors = require('cors');
var path = require('path');
var fs = require('fs');
var net = require('net');

var app = express();
var PORT = parseInt(process.env.PORT, 10) || 3001;
// Сервер слушает только локальный интерфейс: страница открывается в браузере на этом же компьютере.
// Для доступа с других компьютеров задайте HOST=0.0.0.0 (потребуется правило брандмауэра).
var HOST = process.env.HOST || '127.0.0.1';

var DEFAULT_PORTS = '80,443';
var DEFAULT_TIMEOUT = 1000;
var MIN_TIMEOUT = 100;
var MAX_TIMEOUT = 10000;
var MAX_PORTS = 256;
var BATCH_CONCURRENCY = 4;

// Статусы совпадают со значениями из PowerShell-скриптов
var STATUS_OPEN = 'Open';
var STATUS_CLOSED = 'Closed/Unreachable';

app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: false, limit: '10mb' }));
app.use(express.static(path.join(__dirname)));

// ==================== Вспомогательные функции ====================

// Приведение хоста к виду, пригодному для TCP-подключения
function normalizeHost(host) {
    if (host === undefined || host === null) {
        return '';
    }

    var value = String(host).trim();
    if (value === '') {
        return '';
    }

    value = value.replace(/^[A-Za-z][A-Za-z0-9+.\-]*:\/\//, ''); // http:// https:// и т.п.
    value = value.replace(/[\/\\?#].*$/, '');                    // путь и строка запроса

    if (value.charAt(0) === '[') {                               // [::1]:80
        value = value.replace(/^\[/, '').replace(/\](:\d+)?$/, '');
    } else {
        var firstColon = value.indexOf(':');
        if (firstColon !== -1 && value.indexOf(':', firstColon + 1) === -1) {
            value = value.substring(0, firstColon);              // host:port (IPv4 / DNS-имя)
        }
    }

    value = value.trim();

    if (value === '' || !/^[A-Za-z0-9._:\-]+$/.test(value)) {
        return '';
    }

    return value;
}

// Разбор списка портов: "80", "80,443", "80 443", "1-1024", "80,443;8080"
function parsePorts(value) {
    var raw = (value === undefined || value === null || String(value).trim() === '') ? DEFAULT_PORTS : String(value);
    var tokens = raw.split(/[\s,;]+/);
    var ports = [];
    var i;

    for (i = 0; i < tokens.length; i++) {
        var token = tokens[i].trim();
        if (token === '') {
            continue;
        }

        var range = token.match(/^(\d{1,5})-(\d{1,5})$/);
        if (range) {
            var from = parseInt(range[1], 10);
            var to = parseInt(range[2], 10);
            if (from > to) {
                var swap = from;
                from = to;
                to = swap;
            }
            for (var port = from; port <= to; port++) {
                if (port >= 1 && port <= 65535) {
                    ports.push(port);
                }
                if (ports.length >= MAX_PORTS) {
                    break;
                }
            }
        } else if (/^\d{1,5}$/.test(token)) {
            var single = parseInt(token, 10);
            if (single >= 1 && single <= 65535) {
                ports.push(single);
            }
        }

        if (ports.length >= MAX_PORTS) {
            break;
        }
    }

    ports.sort(function (a, b) { return a - b; });

    var unique = [];
    for (i = 0; i < ports.length; i++) {
        if (unique.indexOf(ports[i]) === -1) {
            unique.push(ports[i]);
        }
    }

    return unique.slice(0, MAX_PORTS);
}

// Приведение числового параметра к диапазону
function clampInt(value, defaultValue, min, max) {
    var num = parseInt(value, 10);
    if (isNaN(num)) {
        num = defaultValue;
    }
    if (num < min) {
        num = min;
    }
    if (num > max) {
        num = max;
    }
    return num;
}

// Дата в формате PowerShell-версии: yyyy-MM-dd HH:mm:ss
function formatDateTime(date) {
    function pad(n) { return (n < 10 ? '0' : '') + n; }
    return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' +
           pad(date.getHours()) + ':' + pad(date.getMinutes()) + ':' + pad(date.getSeconds());
}

// Проверка одного порта (аналог функции Test-Port из port_scanner.ps1)
function testPort(host, port, timeout, callback) {
    var socket = new net.Socket();
    var startTime = Date.now();
    var finished = false;

    function done(status, responseTime) {
        if (finished) {
            return;
        }
        finished = true;
        try {
            socket.destroy();
        } catch (e) {
            // сокет уже закрыт
        }
        callback({ port: port, status: status, responseTime: responseTime });
    }

    socket.setTimeout(timeout);
    socket.on('connect', function () {
        done(STATUS_OPEN, Date.now() - startTime);
    });
    socket.on('timeout', function () {
        done(STATUS_CLOSED, null);
    });
    socket.on('error', function () {
        done(STATUS_CLOSED, null);
    });

    try {
        socket.connect(port, host);
    } catch (e) {
        done(STATUS_CLOSED, null);
    }
}

// Последовательная проверка всех портов одного узла
function scanHost(host, ports, timeout, callback) {
    var results = [];
    var startedAt = Date.now();

    function scanNext(index) {
        if (index >= ports.length) {
            var openCount = 0;
            var i;
            for (i = 0; i < results.length; i++) {
                if (results[i].status === STATUS_OPEN) {
                    openCount++;
                }
            }
            callback({
                host: host,
                ports: results,
                openCount: openCount,
                closedCount: results.length - openCount,
                duration: Date.now() - startedAt,
                scanTime: formatDateTime(new Date())
            });
            return;
        }

        testPort(host, ports[index], timeout, function (result) {
            results.push(result);
            scanNext(index + 1);
        });
    }

    scanNext(0);
}

// ==================== API ====================

// GET /api/health - состояние сервера (используется индикатором в интерфейсе)
app.get('/api/health', function (req, res) {
    res.json({
        status: 'ok',
        app: 'WEB_check_ports',
        version: '0.0.1',
        node: process.version,
        platform: process.platform,
        host: HOST,
        port: PORT,
        defaultPorts: parsePorts(DEFAULT_PORTS),
        defaultTimeout: DEFAULT_TIMEOUT,
        time: formatDateTime(new Date())
    });
});

// Размер файла набора данных (байт)
function getFileSize(filename) {
    try {
        return fs.statSync(path.join(__dirname, filename)).size;
    } catch (e) {
        return null;
    }
}

// Тип набора данных определяется по первой строке:
// 'results' - файл результатов сканирования (Hostname,Port,Status,ScanTime)
// 'hosts'   - список узлов (Address;Comment или одна колонка адресов)
function detectDatasetKind(filename) {
    try {
        var buffer = Buffer.alloc(4096);
        var fd = fs.openSync(path.join(__dirname, filename), 'r');
        var bytes = fs.readSync(fd, buffer, 0, 4096, 0);
        fs.closeSync(fd);

        var head = buffer.toString('utf8', 0, bytes).replace(/^\uFEFF/, '');
        var firstLine = head.split(/\r?\n/)[0] || '';

        if (/port/i.test(firstLine) && /(host|address|ip)/i.test(firstLine)) {
            return 'results';
        }
        return 'hosts';
    } catch (e) {
        return 'unknown';
    }
}

// GET /api/datasets - список доступных наборов данных (CSV / TXT в каталоге проекта)
app.get('/api/datasets', function (req, res) {
    try {
        var files = fs.readdirSync(__dirname);
        var datasets = [];
        var details = [];
        var i;

        for (i = 0; i < files.length; i++) {
            var file = files[i];
            if (file.charAt(0) === '.' || file.charAt(0) === '~') {
                continue;
            }
            if (!/\.(csv|txt)$/i.test(file)) {
                continue;
            }
            datasets.push(file);
            details.push({
                name: file,
                kind: detectDatasetKind(file),
                size: getFileSize(file)
            });
        }

        datasets.sort();
        details.sort(function (a, b) {
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
        });

        res.json({ datasets: datasets, files: details });
    } catch (err) {
        res.status(500).json({ error: 'Ошибка чтения директории', message: err.message });
    }
});

// GET /api/dataset/:filename - содержимое выбранного набора данных
app.get('/api/dataset/:filename', function (req, res) {
    var filename = req.params.filename;

    if (filename.indexOf('..') !== -1 ||
        filename.indexOf('/') !== -1 ||
        filename.indexOf('\\') !== -1 ||
        path.isAbsolute(filename)) {
        return res.status(400).json({ error: 'Недопустимое имя файла' });
    }

    if (!/\.(csv|txt)$/i.test(filename)) {
        return res.status(400).json({ error: 'Доступны только CSV и TXT файлы' });
    }

    fs.readFile(path.join(__dirname, filename), function (err, data) {
        if (err) {
            return res.status(404).json({ error: 'Файл не найден', message: err.message });
        }
        res.set('Content-Type', 'text/plain; charset=utf-8');
        res.send(data.toString('utf8').replace(/^\uFEFF/, ''));
    });
});

// GET /api/scan?host=&ports=&timeout= - сканирование одного узла
app.get('/api/scan', function (req, res) {
    var host = normalizeHost(req.query.host);
    var ports = parsePorts(req.query.ports);
    var timeout = clampInt(req.query.timeout, DEFAULT_TIMEOUT, MIN_TIMEOUT, MAX_TIMEOUT);

    if (!host) {
        return res.status(400).json({ error: 'Параметр host обязателен (IP-адрес или DNS-имя)' });
    }
    if (ports.length === 0) {
        return res.status(400).json({ error: 'Не заданы корректные порты (пример: 80,443 или 1-1024)' });
    }

    scanHost(host, ports, timeout, function (result) {
        result.timeout = timeout;
        res.json(result);
    });
});

// POST /api/scan-batch - сканирование нескольких узлов за один запрос
// Тело: { "hosts": ["10.0.0.1", {"address":"10.0.0.2","comment":"DNS"}], "ports": "80,443", "timeout": 1000 }
app.post('/api/scan-batch', function (req, res) {
    var body = req.body || {};
    var input = body.hosts || body.nodes || [];
    var ports = parsePorts(body.ports);
    var timeout = clampInt(body.timeout, DEFAULT_TIMEOUT, MIN_TIMEOUT, MAX_TIMEOUT);

    if (ports.length === 0) {
        return res.status(400).json({ error: 'Не заданы корректные порты (пример: 80,443 или 1-1024)' });
    }

    var prepared = [];
    var seen = {};
    var i;

    for (i = 0; i < input.length; i++) {
        var item = input[i];
        var address = normalizeHost(typeof item === 'string' ? item : item.address);
        if (!address || seen[address.toLowerCase()]) {
            continue;
        }
        seen[address.toLowerCase()] = true;
        prepared.push({
            address: address,
            comment: (typeof item === 'string' || !item.comment) ? '' : String(item.comment)
        });
    }

    if (prepared.length === 0) {
        return res.status(400).json({ error: 'Список узлов пуст или содержит недопустимые адреса' });
    }

    var results = new Array(prepared.length);
    var launched = 0;
    var active = 0;
    var completed = 0;

    function launch() {
        while (active < BATCH_CONCURRENCY && launched < prepared.length) {
            (function (position) {
                var node = prepared[position];
                active++;
                scanHost(node.address, ports, timeout, function (result) {
                    result.comment = node.comment;
                    results[position] = result;
                    active--;
                    completed++;
                    if (completed >= prepared.length) {
                        res.json({
                            total: prepared.length,
                            ports: ports,
                            timeout: timeout,
                            results: results
                        });
                    } else {
                        launch();
                    }
                });
            })(launched);
            launched++;
        }
    }

    launch();
});

// POST /api/save-results - сохранение результатов в CSV-файл в каталоге проекта
// Тело: { "filename": "scan_results.csv", "csv": "Hostname,Port,Status,ScanTime\\r\\n..." }
app.post('/api/save-results', function (req, res) {
    var body = req.body || {};
    var filename = String(body.filename || 'scan_results.csv').trim();
    var csv = body.csv;

    if (typeof csv !== 'string' || csv === '') {
        return res.status(400).json({ error: 'Поле csv обязательно и должно быть строкой' });
    }

    if (!/^[A-Za-z0-9._\-]+\.csv$/i.test(filename) || filename.indexOf('..') !== -1) {
        return res.status(400).json({ error: 'Недопустимое имя файла (разрешены латиница, цифры, . _ - и расширение .csv)' });
    }

    fs.writeFile(path.join(__dirname, filename), csv, 'utf8', function (err) {
        if (err) {
            return res.status(500).json({ error: 'Не удалось сохранить файл', message: err.message });
        }
        res.json({
            saved: true,
            filename: filename,
            size: Buffer.byteLength(csv, 'utf8'),
            time: formatDateTime(new Date())
        });
    });
});

// POST /api/scan-and-save - сканирование узлов и сохранение результата в CSV (полный аналог запуска PS-скрипта)
app.post('/api/scan-and-save', function (req, res) {
    var body = req.body || {};
    var input = body.hosts || [];
    var ports = parsePorts(body.ports);
    var timeout = clampInt(body.timeout, DEFAULT_TIMEOUT, MIN_TIMEOUT, MAX_TIMEOUT);
    var filename = String(body.filename || 'scan_results.csv').trim();
    var scanTime = formatDateTime(new Date());

    if (ports.length === 0) {
        return res.status(400).json({ error: 'Не заданы корректные порты (пример: 80,443 или 1-1024)' });
    }
    if (input.length === 0) {
        return res.status(400).json({ error: 'Список узлов пуст' });
    }
    if (!/^[A-Za-z0-9._\-]+\.csv$/i.test(filename) || filename.indexOf('..') !== -1) {
        return res.status(400).json({ error: 'Недопустимое имя файла результатов' });
    }

    var results = new Array(input.length);
    var launched = 0;
    var active = 0;
    var completed = 0;

    function buildCsv() {
        var lines = ['Hostname,Port,Status,ScanTime'];
        var openCount = 0;
        var i, j;

        for (i = 0; i < results.length; i++) {
            var node = results[i];
            if (!node) {
                continue;
            }
            for (j = 0; j < node.ports.length; j++) {
                if (node.ports[j].status === STATUS_OPEN) {
                    openCount++;
                }
                lines.push('"' + node.host + '",' + node.ports[j].port + ',"' +
                           node.ports[j].status + '","' + scanTime + '"');
            }
        }

        return { csv: lines.join('\r\n') + '\r\n', openCount: openCount };
    }

    function launch() {
        while (active < BATCH_CONCURRENCY && launched < input.length) {
            (function (position) {
                var node = input[position];
                var address = normalizeHost(typeof node === 'string' ? node : node.address);
                active++;
                if (!address) {
                    results[position] = null;
                    active--;
                    completed++;
                    finishOrContinue();
                    return;
                }
                scanHost(address, ports, timeout, function (result) {
                    result.comment = (typeof node === 'string' || !node.comment) ? '' : String(node.comment);
                    results[position] = result;
                    active--;
                    completed++;
                    finishOrContinue();
                });
            })(launched);
            launched++;
        }
    }

    function finishOrContinue() {
        if (completed >= input.length) {
            var built = buildCsv();
            fs.writeFile(path.join(__dirname, filename), built.csv, 'utf8', function (err) {
                if (err) {
                    return res.status(500).json({ error: 'Не удалось сохранить файл', message: err.message });
                }
                res.json({
                    saved: true,
                    filename: filename,
                    scanTime: scanTime,
                    hosts: input.length,
                    ports: ports,
                    openCount: built.openCount,
                    size: Buffer.byteLength(built.csv, 'utf8'),
                    results: results
                });
            });
        } else {
            launch();
        }
    }

    launch();
});

// Раздача интерфейса
app.get('/', function (req, res) {
    res.sendFile(path.join(__dirname, 'index.html'));
});

var server = app.listen(PORT, HOST, function () {
    console.log('');
    console.log('WEB_check_ports v0.0.1 - веб-сканер TCP-портов');
    console.log('Сервер запущен: http://' + HOST + ':' + PORT);
    console.log('Порты по умолчанию: ' + DEFAULT_PORTS + ' (80 - HTTP, 443 - HTTPS)');
    console.log('Таймаут по умолчанию: ' + DEFAULT_TIMEOUT + ' мс');
    console.log('CSV-результат: Hostname,Port,Status,ScanTime (как в port_scanner.ps1)');
    console.log('');
});

server.on('error', function (err) {
    if (err.code === 'EADDRINUSE') {
        console.log('Порт ' + PORT + ' уже занят. Закройте другое приложение или задайте PORT, например: set PORT=3002 && npm start');
    } else {
        console.log('Ошибка запуска сервера: ' + err.message);
    }
    process.exit(1);
});
