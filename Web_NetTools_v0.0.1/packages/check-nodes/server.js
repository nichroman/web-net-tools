var express = require('express');
var cors = require('cors');
var exec = require('child_process').exec;
var path = require('path');
var fs = require('fs');

var app = express();
var PORT = parseInt(process.env.PORT, 10) || 3000;
// Сервер слушает только локальный интерфейс: страница открывается в браузере на этом же компьютере.
// Для доступа с других компьютеров задайте HOST=0.0.0.0 (потребуется правило брандмауэра).
var HOST = process.env.HOST || '127.0.0.1';

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname)));

// --- Разбор вывода системного ping ---------------------------------------
// Windows ping пишет текст в кодировке консоли (в русской Windows это CP866),
// а child_process читает поток как UTF-8. Из-за этого слова "время"/"Ответ"
// превращались в мусор, ни одна строка не совпадала с шаблоном и все узлы
// получали статус "Недоступен". Поэтому поток читается как буфер и
// декодируется подходящей кодировкой.
var PING_CHARSETS = ['utf-8', 'ibm866', 'windows-1251', 'cp437'];
var pingDecoders = [];
if (typeof TextDecoder !== 'undefined') {
    for (var charsetIndex = 0; charsetIndex < PING_CHARSETS.length; charsetIndex++) {
        try {
            pingDecoders.push(new TextDecoder(PING_CHARSETS[charsetIndex]));
        } catch (e) {
            // кодировка недоступна в этой сборке Node.js - пропускаем
        }
    }
}

// Строка ответа ping выглядит так:
//   русская Windows:  "Ответ от 127.0.0.1: число байт=32 время<1мс TTL=128"
//   английская:       "Reply from 127.0.0.1: bytes=32 time<1ms TTL=128"
function parsePingReplyTime(line) {
    var match = line.match(/(?:время|time)\s*[=<]\s*(\d+)\s*(?:мс|ms)/i);
    if (match) {
        return parseInt(match[1], 10);
    }
    return null;
}

// Оценка варианта декодирования: сколько строк похоже на ответы ping
function scorePingText(text) {
    var score = 0;
    var replies = text.match(/(?:время|time)\s*[=<]\s*\d+\s*(?:мс|ms)/gi);
    if (replies) {
        score += replies.length * 10;
    }
    var ttl = text.match(/TTL\s*=\s*\d+/gi);
    if (ttl) {
        score += ttl.length;
    }
    if (/(?:Ответ от|Reply from|Пакетов:|Packets:)/i.test(text)) {
        score += 1;
    }
    return score;
}

// Декодирование буфера вывода ping: выбирается кодировка с наибольшим числом
// распознанных ответов (для английской локали все варианты совпадают)
function decodePingOutput(buffer) {
    if (!Buffer.isBuffer(buffer)) {
        if (buffer === undefined || buffer === null) {
            return '';
        }
        return String(buffer);
    }

    var best = null;
    var bestScore = -1;

    for (var i = 0; i < pingDecoders.length; i++) {
        var text = pingDecoders[i].decode(buffer);
        var score = scorePingText(text);
        if (score > bestScore) {
            bestScore = score;
            best = text;
        }
    }

    if (best === null) {
        best = buffer.toString('utf8');
    }
    return best;
}

// Проверка узла через системный ping
function pingHost(host, count, timeout, callback) {
    // Windows: ping -n count -w timeout host
    var command = 'ping -n ' + count + ' -w ' + timeout + ' ' + host;

    // encoding: 'buffer' - читаем сырые байты, чтобы декодировать их правильно
    exec(command, { timeout: (timeout * count) + 5000, encoding: 'buffer' }, function(error, stdout, stderr) {
        var output = decodePingOutput(stdout);

        if (!output) {
            return callback(null, {
                alive: false,
                avgTime: null,
                minTime: null,
                maxTime: null,
                lostPercent: 100,
                successCount: 0
            });
        }

        var lines = output.split(/\r?\n/);
        var successCount = 0;
        var totalTime = 0;
        var times = [];

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var time = parsePingReplyTime(line);
            if (time !== null) {
                times.push(time);
                successCount++;
                totalTime += time;
                continue;
            }
            // Страховка для других языков и кодировок: строка ответа всегда
            // содержит "TTL=", поэтому узел всё равно считается доступным
            if (/TTL\s*=\s*\d+/i.test(line)) {
                successCount++;
            }
        }

        var lostPercent = Math.round(((count - successCount) / count) * 100);
        if (lostPercent < 0) {
            lostPercent = 0;
        }
        var avgTime = times.length > 0 ? Math.round(totalTime / times.length) : null;
        var minTime = times.length > 0 ? Math.min.apply(null, times) : null;
        var maxTime = times.length > 0 ? Math.max.apply(null, times) : null;

        callback(null, {
            alive: successCount > 0,
            avgTime: avgTime,
            minTime: minTime,
            maxTime: maxTime,
            lostPercent: lostPercent,
            successCount: successCount
        });
    });
}

// API: состояние сервера (используется лаунчером Web_NetTools и для проверки работоспособности)
app.get('/api/health', function(req, res) {
    res.json({
        status: 'ok',
        app: 'WEB_check_nodes',
        version: '0.0.4',
        node: process.version,
        platform: process.platform,
        host: HOST,
        port: PORT,
        time: new Date().toISOString()
    });
});

// API: список доступных наборов данных (CSV файлы)
app.get('/api/datasets', function(req, res) {
    var dir = __dirname;
    var files = [];
    
    try {
        var allFiles = fs.readdirSync(dir);
        for (var i = 0; i < allFiles.length; i++) {
            var file = allFiles[i];
            if (file.toLowerCase().indexOf('.csv') !== -1) {
                files.push(file);
            }
        }
        files.sort();
        res.json({ datasets: files });
    } catch (err) {
        res.status(500).json({ error: 'Ошибка чтения директории', message: err.message });
    }
});

// API: получение содержимого CSV файла
app.get('/api/dataset/:filename', function(req, res) {
    var filename = req.params.filename;
    // Защита от path traversal
    if (filename.indexOf('..') !== -1 || path.isAbsolute(filename)) {
        return res.status(400).json({ error: 'Недопустимое имя файла' });
    }
    
    var filePath = path.join(__dirname, filename);
    
    if (!filename.toLowerCase().endsWith('.csv')) {
        return res.status(400).json({ error: 'Доступны только CSV файлы' });
    }
    
    fs.readFile(filePath, 'utf8', function(err, data) {
        if (err) {
            return res.status(404).json({ error: 'Файл не найден', message: err.message });
        }
        res.set('Content-Type', 'text/csv; charset=utf-8');
        res.send(data);
    });
});

// API: проверка одного узла
app.get('/api/ping', function(req, res) {
    var host = req.query.host;
    var count = parseInt(req.query.count, 10) || 10;
    var timeout = parseInt(req.query.timeout, 10) || 1000;

    if (!host) {
        return res.status(400).json({ error: 'Параметр host обязателен' });
    }

    count = Math.min(Math.max(count, 1), 100);
    timeout = Math.min(Math.max(timeout, 100), 5000);

    pingHost(host, count, timeout, function(err, result) {
        if (err) {
            return res.status(500).json({ error: 'Ошибка проверки', message: err.message });
        }

        var status;
        if (result.successCount === 0) {
            status = 'Недоступен';
        } else if (result.lostPercent === 0) {
            status = 'Доступен';
        } else if (result.lostPercent < 50) {
            status = 'Частично доступен';
        } else {
            status = 'Недоступен';
        }

        res.json({
            host: host,
            status: status,
            avgTime: result.avgTime,
            minTime: result.minTime,
            maxTime: result.maxTime,
            lostPercent: result.lostPercent,
            successPackets: result.successCount + '/' + count,
            totalPackets: count,
            successCount: result.successCount
        });
    });
});

// Раздача HTML
app.get('/', function(req, res) {
    res.sendFile(path.join(__dirname, 'index.html'));
});

var server = app.listen(PORT, HOST, function() {
    console.log('');
    console.log('WEB_check_nodes v0.0.4 - проверка доступности сетевых узлов');
    console.log('Сервер запущен: http://' + HOST + ':' + PORT);
    console.log('Откройте браузер для проверки узлов');
    console.log('');
});

server.on('error', function(err) {
    if (err.code === 'EADDRINUSE') {
        console.log('Порт ' + PORT + ' уже занят. Закройте другое приложение или задайте PORT, например: set PORT=3002 && npm start');
    } else {
        console.log('Ошибка запуска сервера: ' + err.message);
    }
    process.exit(1);
});