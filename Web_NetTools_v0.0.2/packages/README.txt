ПАПКА packages - ПРИЛОЖЕНИЯ, КОТОРЫЕ УСТАНАВЛИВАЕТ ДИСТРИБУТИВ
==============================================================

Здесь лежат готовые к установке утилиты, поэтому дистрибутив самодостаточен:
install.bat находит их автоматически и не требует соседних каталогов.

    packages\check-nodes\   WEB_check_nodes v0.0.4 - проверка узлов (ping), порт 3000
                            server.js, index.html, package.json, node_modules, *_nodes.csv
    packages\check-ports\   WEB_check_ports v0.0.1 - сканер TCP-портов, порт 3001
                            server.js, index.html, package.json, node_modules, hosts.csv
    packages\VERSION.txt    что и когда скопировано (создаёт update-packages.ps1)

Зависимости (node_modules: express, cors) уже входят в поставку, поэтому для
установки на целевой машине нужен только Node.js - ни npm, ни доступ в интернет
не требуются.

ОБНОВЛЕНИЕ ПРИЛОЖЕНИЙ В ДИСТРИБУТИВЕ
-----------------------------------
    powershell -NoProfile -ExecutionPolicy Bypass -File ..\update-packages.ps1 -Force

Скрипт update-packages.ps1 (лежит рядом с install.bat) копирует актуальное
содержимое проектов-источников в packages\check-nodes и packages\check-ports:

    ..\WEB_check_nodes_v0.0.4  ->  packages\check-nodes
    ..\WEB_check_ports_v0.0.1  ->  packages\check-ports

Пути можно задать явно:

    ... -File update-packages.ps1 -NodesSource "C:\distr\WEB_check_nodes_v0.0.4" -PortsSource "C:\distr\WEB_check_ports_v0.0.1" -Force

Полезно перед обновлением выполнить npm install в каталоге-источнике, чтобы
в дистрибутив попали актуальные зависимости.

Порядок поиска приложений установщиком
--------------------------------------
1) параметр -NodesSource / -PortsSource;
2) эта папка packages (каталог check-nodes / check-ports);
3) каталог установщика и соседние с ним каталоги (в том числе вложенные);
4) общие и пользовательские папки (C:\Users\Public\Desktop, Desktop, Downloads,
   Documents, C:\distr, C:\Tools).

Программа определяется по содержимому server.js, поэтому имена папок могут быть
любыми, а вложенность допустима.

Результат установки не зависит от места исходников: программы копируются в общий
каталог C:\Tools\WebNetTools с правами "Изменение" для группы "Пользователи",
ярлыки создаются на общем рабочем столе (C:\Users\Public\Desktop) и в общем
меню "Пуск" - то есть доступны всем пользователям компьютера.
